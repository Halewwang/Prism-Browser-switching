import AppKit
import Observation
import PrismCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
protocol AppRootCustomBrowserSaving: AnyObject {
    func saveCustomBrowser(at applicationURL: URL) throws -> BrowserDescriptor
}

extension BrowserCatalogService: AppRootCustomBrowserSaving {}

@MainActor
struct AppRootSystemActions {
    typealias URLSelection = @MainActor () async -> URL?
    typealias SystemAction = @MainActor () -> Bool

    private let chooseCustomBrowserApplication: URLSelection
    private let customBrowserSaver: (any AppRootCustomBrowserSaving)?
    private let openDefaultAppsSettingsAction: SystemAction
    private let openApplicationsFolderAction: SystemAction
    private let restartAction: SystemAction

    init(
        chooseCustomBrowserApplication: @escaping URLSelection,
        customBrowserSaver: (any AppRootCustomBrowserSaving)?,
        openDefaultAppsSettings: @escaping SystemAction,
        openApplicationsFolder: @escaping SystemAction,
        restart: @escaping SystemAction
    ) {
        self.chooseCustomBrowserApplication = chooseCustomBrowserApplication
        self.customBrowserSaver = customBrowserSaver
        openDefaultAppsSettingsAction = openDefaultAppsSettings
        openApplicationsFolderAction = openApplicationsFolder
        restartAction = restart
    }

    static let inert = AppRootSystemActions(
        chooseCustomBrowserApplication: { nil },
        customBrowserSaver: nil,
        openDefaultAppsSettings: { false },
        openApplicationsFolder: { false },
        restart: { false }
    )

    static func production(
        customBrowserSaver: (any AppRootCustomBrowserSaving)?
    ) -> AppRootSystemActions {
        AppRootSystemActions(
            chooseCustomBrowserApplication: {
                let panel = NSOpenPanel()
                panel.title = "Add Custom Browser"
                panel.message = "Choose a browser application."
                panel.prompt = "Add Browser"
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.allowedContentTypes = [.application]
                guard panel.runModal() == .OK else { return nil }
                return panel.url
            },
            customBrowserSaver: customBrowserSaver,
            openDefaultAppsSettings: {
                let settingsURL = URL(
                    fileURLWithPath: "/System/Applications/System Settings.app",
                    isDirectory: true
                )
                return NSWorkspace.shared.open(settingsURL)
            },
            openApplicationsFolder: {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
            },
            restart: {
                guard let executableURL = Bundle.main.executableURL else { return false }
                do {
                    try Process.run(executableURL, arguments: [])
                    NSApp.terminate(nil)
                    return true
                } catch {
                    return false
                }
            }
        )
    }

    func addCustomBrowser() async -> OnboardingCustomBrowserResult {
        guard let selectedURL = await chooseCustomBrowserApplication() else {
            return .cancelled
        }
        guard selectedURL.isFileURL,
              selectedURL.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame,
              let customBrowserSaver
        else {
            return .failed
        }
        do {
            _ = try customBrowserSaver.saveCustomBrowser(at: selectedURL)
            return .added
        } catch {
            return .failed
        }
    }

    @discardableResult
    func openDefaultAppsSettings() -> Bool {
        openDefaultAppsSettingsAction()
    }

    @discardableResult
    func openApplicationsFolder() -> Bool {
        openApplicationsFolderAction()
    }

    @discardableResult
    func restart() -> Bool {
        restartAction()
    }
}

@MainActor
struct AppRootRecoveryDispatcher {
    typealias Retry = @MainActor () async -> Bool
    typealias Restart = @MainActor () -> Bool

    private let retryPendingTerminalHistory: Retry
    private let retryRestoration: Retry
    private let retryPendingPersistence: Retry
    private let resumeRouting: Retry
    private let restart: Restart

    init(
        retryPendingTerminalHistory: @escaping Retry,
        retryRestoration: @escaping Retry,
        retryPendingPersistence: @escaping Retry,
        resumeRouting: @escaping Retry,
        restart: @escaping Restart
    ) {
        self.retryPendingTerminalHistory = retryPendingTerminalHistory
        self.retryRestoration = retryRestoration
        self.retryPendingPersistence = retryPendingPersistence
        self.resumeRouting = resumeRouting
        self.restart = restart
    }

    @discardableResult
    func perform(_ action: AppRecoveryAction) async -> Bool {
        switch action {
        case .retryHistory:
            await retryPendingTerminalHistory()
        case .retryRestoration:
            await retryRestoration()
        case .retryPendingPersistence:
            await retryPendingPersistence()
        case .resumeRouting:
            await resumeRouting()
        case .restart:
            restart()
        }
    }
}

struct AppRootRecoveryRendering {
    let action: AppRecoveryAction
    let pageState: PageStateModel?
    let banner: RecoveryBannerModel?

    init?(
        presentation: AppRootPresentation,
        isPerformingAction: Bool = false
    ) {
        guard let recovery = presentation.recovery else { return nil }
        action = recovery.primaryAction.action
        let pageAction = PageStateAction(
            id: recovery.primaryAction.accessibilityIdentifier,
            title: recovery.primaryAction.title,
            accessibilityIdentifier: recovery.primaryAction.accessibilityIdentifier
        )
        if presentation.kind == .recovery {
            pageState = .recovery(
                title: recovery.title,
                message: recovery.message,
                action: pageAction,
                isPerformingAction: isPerformingAction
            )
            banner = nil
        } else {
            pageState = nil
            banner = RecoveryBannerModel(
                kind: Self.bannerKind(for: recovery.reason),
                title: recovery.title,
                message: recovery.message,
                actionTitle: recovery.primaryAction.title,
                actionAccessibilityIdentifier: recovery.primaryAction.accessibilityIdentifier,
                isPerformingAction: isPerformingAction
            )
        }
    }

    func onboardingBanner(suppressing alert: OnboardingAlert?) -> RecoveryBannerModel? {
        if case .settingsNotSaved = alert, action == .restart {
            return nil
        }
        return banner
    }

    private static func bannerKind(for reason: AppRecoveryReason) -> RecoveryBannerKind {
        switch reason {
        case .pendingTerminalHistory, .historyNotSaved:
            .historyReconciliationPending
        case .corruptStoreRecovered, .runtimePendingPersistence, .runtimeRoutingPaused,
             .runtimeStorageUnavailable, .settingsNotSaved, .startupRestoration:
            .corruptDataRecovered
        }
    }
}

@MainActor
@Observable
final class AppRootRecoveryController {
    private let dispatcher: AppRootRecoveryDispatcher
    private(set) var isPerformingAction = false

    init(dispatcher: AppRootRecoveryDispatcher) {
        self.dispatcher = dispatcher
    }

    func perform(_ action: AppRecoveryAction) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        let recoveryDispatcher = dispatcher
        Task { @MainActor [weak self, recoveryDispatcher] in
            _ = await recoveryDispatcher.perform(action)
            self?.isPerformingAction = false
        }
    }
}

@MainActor
struct AppRootShellCommands {
    let environment: AppEnvironment

    func openSettings() {
        environment.updateRoute(.settings)
    }

    func checkForUpdates() {
        environment.updateChecker.checkForUpdates()
    }
}

@MainActor
@Observable
final class AppRootCoordinator {
    let onboardingModel: OnboardingViewModel
    let historyModel: HistoryViewModel

    private let composition: ProductionAppComposition
    private let systemActions: AppRootSystemActions
    private let recoveryController: AppRootRecoveryController
    private var shellTestLinkSession: OnboardingTestLinkSession?
    private var shellTestLinkGeneration: UUID?

    init(
        composition: ProductionAppComposition,
        systemActions: AppRootSystemActions? = nil
    ) {
        self.composition = composition
        let resolvedSystemActions = systemActions ?? .production(
            customBrowserSaver: composition.browserCatalog as? any AppRootCustomBrowserSaving
        )
        self.systemActions = resolvedSystemActions
        onboardingModel = OnboardingViewModel(
            environment: composition.environment,
            defaultBrowserService: composition.defaultBrowserService,
            browserCatalog: composition.browserCatalog,
            testLinkRouter: composition.onboardingTestLinkRouter,
            openMainWindow: { [weak composition] route in
                composition?.mainWindowOpening.open(route: route)
            },
            resumeRouting: { [weak composition] in
                await composition?.resumeRoutingAfterOnboardingCompletion()
            }
        )
        let clipboard: any HistoryClipboardWriting = systemActions == nil
            ? SystemHistoryClipboard()
            : DiscardingHistoryClipboard()
        historyModel = HistoryViewModel(
            historyService: composition.environment.historyService,
            queue: composition.recoveryQueue,
            settings: { [weak composition] in composition?.environment.settings ?? .conservativePersistenceFallback },
            coordinator: composition.linkRoutingCoordinator,
            intake: composition.linkIntakeService,
            clipboard: clipboard,
            navigation: composition.environment
        )
        recoveryController = AppRootRecoveryController(dispatcher: AppRootRecoveryDispatcher(
            retryPendingTerminalHistory: { [weak composition] in
                await composition?.retryPendingTerminalHistory() ?? false
            },
            retryRestoration: { [weak composition] in
                await composition?.retryRestorationAfterUserAction() ?? false
            },
            retryPendingPersistence: { [weak composition] in
                await composition?.retryPendingPersistenceAfterUserAction() ?? false
            },
            resumeRouting: { [weak composition] in
                await composition?.resumeRoutingAfterRecoveryUserAction() ?? false
            },
            restart: { resolvedSystemActions.restart() }
        ))
    }

    var presentation: AppRootPresentation {
        AppRootPresentation(
            startupPhase: environment.startupPhase,
            hasPendingTerminalHistoryReconciliation: environment.hasPendingTerminalHistoryReconciliation,
            runtimeLinkRecoveryState: composition.runtimeLinkRecoveryState,
            persistenceWarnings: environment.persistenceWarnings
        )
    }

    var routeBinding: Binding<AppRoute> {
        environment.sharedRouteBinding
    }

    var onboardingActions: OnboardingViewActions {
        OnboardingViewActions(
            addCustomBrowser: { [systemActions] in
                await systemActions.addCustomBrowser()
            },
            openDefaultAppsSettings: { [systemActions] in
                systemActions.openDefaultAppsSettings()
            },
            openApplicationsFolder: { [systemActions] in
                systemActions.openApplicationsFolder()
            }
        )
    }

    var shellActions: AppShellActions {
        return AppShellActions(
            testLink: { [weak self] in self?.startShellTestLink() },
            openApplicationsFolder: { [systemActions] in
                systemActions.openApplicationsFolder()
            },
            openDefaultAppsSettings: { [systemActions] in
                systemActions.openDefaultAppsSettings()
            }
        )
    }

    func addCustomBrowser() async -> OnboardingCustomBrowserResult {
        let result = await systemActions.addCustomBrowser()
        if result == .added {
            _ = try? await composition.browserCatalog.scan()
        }
        return result
    }

    var recoveryRendering: AppRootRecoveryRendering? {
        AppRootRecoveryRendering(
            presentation: presentation,
            isPerformingAction: recoveryController.isPerformingAction
        )
    }

    var environment: AppEnvironment {
        composition.environment
    }

    var browserCatalog: any BrowserCataloging {
        composition.browserCatalog
    }

    func checkForUpdates() {
        AppRootShellCommands(environment: environment).checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        environment.updateChecker.canCheckForUpdates
    }

    func openSettings() {
        AppRootShellCommands(environment: environment).openSettings()
    }

    func performRecoveryAction() {
        guard let action = recoveryRendering?.action else { return }
        recoveryController.perform(action)
    }

    private func startShellTestLink() {
        guard shellTestLinkGeneration == nil, shellTestLinkSession == nil else { return }
        let generation = UUID()
        shellTestLinkGeneration = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            let session = await composition.onboardingTestLinkRouter.start(
                url: URL(string: "https://example.com/prism-test")!,
                onPrepared: { [weak self] preparedSession in
                    guard let self, self.shellTestLinkGeneration == generation else { return false }
                    self.shellTestLinkSession = preparedSession
                    return true
                },
                onOutcome: { [weak self] outcome in
                    guard let self, self.shellTestLinkSession?.requestID == outcome.requestID else {
                        return false
                    }
                    if outcome.kind.isTerminal {
                        self.shellTestLinkSession = nil
                        self.shellTestLinkGeneration = nil
                        return false
                    }
                    return true
                }
            )
            guard self.shellTestLinkGeneration == generation else {
                if let session { _ = await session.cancel() }
                return
            }
            self.shellTestLinkGeneration = nil
            self.shellTestLinkSession = session
        }
    }

}

struct AppRootView: View {
    @State private var coordinator: AppRootCoordinator

    init(
        composition: ProductionAppComposition,
        systemActions: AppRootSystemActions? = nil
    ) {
        _coordinator = State(initialValue: AppRootCoordinator(
            composition: composition,
            systemActions: systemActions
        ))
    }

    var body: some View {
        rootContent
            .frame(minWidth: 760, minHeight: 520)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(coordinator.environment)
    }

    @ViewBuilder
    private var rootContent: some View {
        switch coordinator.presentation.kind {
        case .loading:
            PageStateView(model: .loading(
                title: "Opening Prism",
                message: "Restoring your settings and pending links…"
            ))
        case .onboarding:
            VStack(spacing: 0) {
                if let banner = coordinator.recoveryRendering?.onboardingBanner(
                    suppressing: coordinator.onboardingModel.alert
                ) {
                    RecoveryBanner(
                        model: banner,
                        onAction: coordinator.performRecoveryAction
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                OnboardingView(
                    model: coordinator.onboardingModel,
                    actions: coordinator.onboardingActions,
                    fillsMinimumWindowSize: false
                )
                .frame(maxHeight: .infinity)
            }
        case .shell:
            AppShellView(
                route: coordinator.routeBinding,
                actions: coordinator.shellActions,
                historyModel: coordinator.historyModel,
                browserCatalog: coordinator.browserCatalog,
                addCustomBrowser: { await coordinator.addCustomBrowser() },
                recoveryBanner: coordinator.recoveryRendering?.banner,
                onRecoveryAction: coordinator.performRecoveryAction
            )
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        coordinator.openSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                    }
                    .accessibilityIdentifier("appShell.openSettings")

                    if coordinator.canCheckForUpdates {
                        Button {
                            coordinator.checkForUpdates()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.clockwise")
                        }
                        .accessibilityIdentifier("appShell.checkForUpdates")
                    }
                }
            }
        case .recovery:
            if let state = coordinator.recoveryRendering?.pageState {
                PageStateView(model: state) { _ in
                    coordinator.performRecoveryAction()
                }
            } else {
                PageStateView(model: .loading(title: "Opening Prism"))
            }
        }
    }
}
