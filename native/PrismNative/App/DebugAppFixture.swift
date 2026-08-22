#if DEBUG
import AppKit
import Foundation
import PrismCore
import SwiftUI

enum DebugAppFixtureVariant: String, CaseIterable, Equatable, Sendable {
    case onboarding
    case partialHandler = "partial-handler"
    case emptyBrowsers = "empty-browsers"
    case launchFailure = "launch-failure"
    case onboardingRecovery = "onboarding-recovery"
    case shell
    case workspace
    case recovery
    case history
    case historyLoadFailure = "history-load-failure"
    case historyNoURL = "history-no-url"
    case historyUnsafeURL = "history-unsafe-url"
    case historyActions = "history-actions"

    static func parse(arguments: [String]) -> DebugAppFixtureVariant {
        guard let index = arguments.firstIndex(of: "--app-fixture"),
              arguments.indices.contains(index + 1),
              let variant = DebugAppFixtureVariant(rawValue: arguments[index + 1])
        else {
            return .onboarding
        }
        return variant
    }
}

@MainActor
final class DebugUITestEffectRecorder {
    private(set) var defaultHandlerReadCount = 0
    private(set) var defaultHandlerWriteCount = 0
    private(set) var browserScanCount = 0
    private(set) var browserHandoffCount = 0
    private(set) var fixtureActivationObserverRegistrationCount = 0
    private(set) var statusItemInstallCount = 0
    private(set) var statusItemVisibilityValues: [Bool] = []

    func recordDefaultHandlerRead() { defaultHandlerReadCount += 1 }
    func recordDefaultHandlerWrite() { defaultHandlerWriteCount += 1 }
    func recordBrowserScan() { browserScanCount += 1 }
    func recordBrowserHandoff() { browserHandoffCount += 1 }
    func recordFixtureActivationObserverRegistration() {
        fixtureActivationObserverRegistrationCount += 1
    }
    func recordStatusItemInstall() { statusItemInstallCount += 1 }
    func recordStatusItemVisibility(_ value: Bool) { statusItemVisibilityValues.append(value) }
}

@MainActor
final class DebugNoopStatusItemHost: StatusItemHosting {
    private let recorder: DebugUITestEffectRecorder

    init(recorder: DebugUITestEffectRecorder) {
        self.recorder = recorder
    }

    func install(menu _: NSMenu) {
        recorder.recordStatusItemInstall()
    }

    func setVisible(_ isVisible: Bool) {
        recorder.recordStatusItemVisibility(isVisible)
    }
}

/// Keeps UI-test application fixtures foreground-active until SwiftUI creates
/// the real main window. The anchor is invisible to accessibility and exists
/// only in DEBUG builds, so it cannot become a second user-facing Prism window.
@MainActor
protocol DebugAppFixtureApplicationActivating: AnyObject {
    func activate(options: NSApplication.ActivationOptions)
}

@MainActor
private final class SystemDebugAppFixtureApplicationActivator: DebugAppFixtureApplicationActivating {
    func activate(options: NSApplication.ActivationOptions) {
        _ = NSRunningApplication.current.activate(options: options)
    }
}

@MainActor
final class DebugAppFixtureActivationAnchor {
    static let foregroundActivationOptions: NSApplication.ActivationOptions = [
        .activateAllWindows,
        .activateIgnoringOtherApps,
    ]

    private final class ActivationWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private let window: NSWindow
    private let applicationActivator: any DebugAppFixtureApplicationActivating

    init(applicationActivator: any DebugAppFixtureApplicationActivating = SystemDebugAppFixtureApplicationActivator()) {
        self.applicationActivator = applicationActivator
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(
            x: 0,
            y: 0,
            width: 760,
            height: 520
        )
        let size = CGSize(width: 760, height: 520)
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        let window = ActivationWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setAccessibilityElement(false)
        self.window = window
    }

    func activate() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        Self.requestForeground(using: applicationActivator)
    }

    func deactivate() {
        window.orderOut(nil)
    }

    static func requestForeground(using applicationActivator: any DebugAppFixtureApplicationActivating) {
        applicationActivator.activate(options: foregroundActivationOptions)
    }
}

enum DebugApplicationFixtureAppearance: Equatable {
    case light
    case dark

    init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-AppleInterfaceStyle"),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }

        switch arguments[index + 1].lowercased() {
        case "light":
            self = .light
        case "dark":
            self = .dark
        default:
            return nil
        }
    }

    static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        interfaceStylePreference: String? = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
    ) -> Self? {
        if let explicitArgument = Self(arguments: arguments) {
            return explicitArgument
        }
        guard let interfaceStylePreference else { return nil }
        return Self(arguments: ["-AppleInterfaceStyle", interfaceStylePreference])
    }

    var nsAppearance: NSAppearance {
        switch self {
        case .light:
            NSAppearance(named: .aqua)!
        case .dark:
            NSAppearance(named: .darkAqua)!
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
struct DebugAppFixture {
    let composition: ProductionAppComposition
    let recorder: DebugUITestEffectRecorder

    static func make(
        bootstrapBuffer: BootstrapLinkBuffer,
        variant: DebugAppFixtureVariant = .parse(arguments: ProcessInfo.processInfo.arguments)
    ) -> DebugAppFixture {
        let recorder = DebugUITestEffectRecorder()
        let browsers = Self.browsers(for: variant)
        let catalog = DebugAppBrowserCatalog(browsers: browsers, recorder: recorder)
        let settingsRepository = InMemorySettingsRepository()
        if Self.opensHistoryInShell(variant) {
            var settings = AppSettings.defaults
            settings.onboardingCompleted = true
            try? settingsRepository.save(settings)
        }
        let historyRepository: any HistoryRepository = variant == .historyLoadFailure
            ? DebugHistoryLoadFailingRepository()
            : InMemoryHistoryRepository()
        for entry in Self.historyEntries(for: variant) {
            try? historyRepository.upsert(entry)
        }
        let ruleRepository = InMemoryRuleRepository()
        for rule in Self.rules(for: variant, browsers: browsers) {
            try? ruleRepository.upsert(rule)
        }
        let environment = AppEnvironment(
            route: variant == .workspace ? .overview : .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: ruleRepository,
            historyRepository: historyRepository,
            browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
            settingsRepository: settingsRepository
        )
        if variant == .onboardingRecovery {
            environment.present(.corruptStoreRecovered(backupLocation: "/tmp/prism-fixture-backup"))
        }
        let queue = LinkRequestQueue(store: DebugUITestPendingRequestStore(
            initialSnapshot: Self.pendingSnapshot(for: variant),
            failsLoad: variant == .recovery
        ))
        let relay = SelectorPresentationRelay()
        let launcher = DebugAppBrowserLauncher(
            recorder: recorder,
            rejectsHandoff: variant == .launchFailure
        )
        let coordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: environment.ruleRepository,
            historyRepository: environment.historyRepository,
            historyService: environment.historyService,
            settingsRepository: environment.settingsRepository,
            browserCatalog: catalog,
            browserLauncher: launcher,
            sourceManifest: .disabled,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion,
            presenter: relay,
            warningPresenter: environment
        )
        let intake = LinkIntakeService(
            queue: queue,
            bootstrap: bootstrapBuffer,
            sourceAttributor: DebugAppSourceAttributor(),
            lastActivatedSource: { nil },
            coordinator: coordinator,
            warningPresenter: environment
        )
        coordinator.continuationRequester = intake
        let defaultHandlerClient = DebugAppDefaultHandlerClient(
            recorder: recorder,
            initialHandlers: Self.initialHandlers(for: variant)
        )
        let defaultBrowserService = DefaultBrowserService(
            client: defaultHandlerClient,
            applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
            bundleIdentifier: "com.prism.app"
        )
        let loginItemService = LoginItemService(client: DebugAppLoginItemClient())
        environment.connectLinkRouting(
            coordinator: coordinator,
            intake: intake,
            defaultBrowserService: defaultBrowserService,
            loginItemService: loginItemService
        )
        let composition = ProductionAppComposition(
            environment: environment,
            recoveryQueue: queue,
            warningSource: nil,
            bootstrapBuffer: bootstrapBuffer,
            linkRoutingCoordinator: coordinator,
            linkIntakeService: intake,
            defaultBrowserService: defaultBrowserService,
            loginItemService: loginItemService,
            selectorPresentationRelay: relay,
            activationTracker: ApplicationActivationTracker(
                observer: DebugAppActivationObserver(recorder: recorder)
            ),
            browserCatalog: catalog,
            sourceManifest: .disabled,
            iconProvider: DebugAppIconProvider()
        )
        return DebugAppFixture(composition: composition, recorder: recorder)
    }

    private static func initialHandlers(for variant: DebugAppFixtureVariant) -> [String: String] {
        switch variant {
        case .onboarding, .onboardingRecovery, .launchFailure, .shell, .recovery,
             .history, .historyLoadFailure, .historyNoURL, .historyUnsafeURL, .historyActions:
            [:]
        case .workspace:
            ["http": "com.prism.app", "https": "com.prism.app"]
        case .partialHandler:
            ["http": "com.prism.app"]
        case .emptyBrowsers:
            ["http": "com.prism.app", "https": "com.prism.app"]
        }
    }

    private static func opensHistoryInShell(_ variant: DebugAppFixtureVariant) -> Bool {
        switch variant {
        case .shell, .workspace, .history, .historyLoadFailure, .historyNoURL, .historyUnsafeURL, .historyActions:
            true
        case .onboarding, .partialHandler, .emptyBrowsers, .launchFailure,
             .onboardingRecovery, .recovery:
            false
        }
    }

    private static func historyEntries(for variant: DebugAppFixtureVariant) -> [HistoryEntry] {
        switch variant {
        case .history:
            [
                historyEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                    url: URL(string: "https://history.example/opened?safe=visible")!,
                    result: .success,
                    targetName: "Fixture Browser",
                    method: .urlRule
                ),
                historyEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                    url: URL(string: "https://history.example/cancelled?safe=visible")!,
                    result: .cancelled,
                    targetName: nil,
                    method: nil
                ),
            ]
        case .historyNoURL:
            [
                historyEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                    url: nil,
                    result: .cancelled,
                    targetName: nil,
                    method: nil
                ),
            ]
        case .historyUnsafeURL:
            [
                historyEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000206")!,
                    url: URL(string: "https://username:password@history.example/private?token=secret&password=redacted&api_key=redacted&client_secret=redacted&refresh_token=redacted&safe=visible#fragment")!,
                    result: .cancelled,
                    targetName: nil,
                    method: nil
                ),
            ]
        case .historyActions:
            [
                historyEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
                    url: URL(string: "https://history.example/failed?safe=visible")!,
                    result: .failure,
                    targetName: "Fixture Browser",
                    method: .manual,
                    failureReason: "launch_failed"
                ),
                historyEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000205")!,
                    url: URL(string: "https://history.example/opened?safe=visible")!,
                    result: .success,
                    targetName: "Fixture Browser",
                    method: .preferredBrowser
                ),
            ]
        case .onboarding, .partialHandler, .emptyBrowsers, .launchFailure,
             .onboardingRecovery, .shell, .workspace, .recovery, .historyLoadFailure:
            []
        }
    }

    private static func browsers(for variant: DebugAppFixtureVariant) -> [BrowserDescriptor] {
        if variant == .emptyBrowsers { return [] }
        if variant == .workspace {
            return [
                browser(id: "com.apple.Safari", name: "Safari", order: 0),
                browser(id: "com.google.Chrome", name: "Chrome", order: 1),
                browser(id: "company.thebrowser.Browser", name: "Arc", order: 2),
            ]
        }
        return [browser(id: "invalid.prism.fixture.browser", name: "Fixture Browser", order: 0)]
    }

    private static func browser(id: String, name: String, order: Int) -> BrowserDescriptor {
        BrowserDescriptor(
            id: BrowserID(id),
            bundleIdentifier: id,
            displayName: name,
            applicationURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            securityScopedBookmark: nil,
            origin: .system,
            availability: .available,
            selectorOrder: order
        )
    }

    private static func rules(
        for variant: DebugAppFixtureVariant,
        browsers: [BrowserDescriptor]
    ) -> [RoutingRule] {
        guard variant == .workspace,
              browsers.count == 3
        else { return [] }
        let now = Date(timeIntervalSince1970: 1_724_328_000)
        return [
            RoutingRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                isEnabled: true,
                matcher: .hostAndSubdomains("docs.example.com"),
                targetBrowserID: browsers[1].id,
                priority: 0,
                label: "Documentation",
                createdAt: now,
                updatedAt: now
            ),
            RoutingRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                isEnabled: true,
                matcher: .exactHost("calendar.example.com"),
                targetBrowserID: browsers[0].id,
                priority: 1,
                label: "Calendar",
                createdAt: now,
                updatedAt: now
            ),
            RoutingRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
                isEnabled: true,
                matcher: .sourceBundleIdentifier("com.example.messages"),
                targetBrowserID: browsers[2].id,
                priority: 0,
                label: "Messages",
                createdAt: now,
                updatedAt: now
            ),
        ]
    }

    private static func pendingSnapshot(for variant: DebugAppFixtureVariant) -> PendingRequestSnapshot {
        guard variant == .historyActions else {
            return PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])
        }
        let requestID = UUID(uuidString: "00000000-0000-0000-0000-000000000204")!
        return PendingRequestSnapshot(
            pendingRequests: [
                LinkRequest(
                    id: requestID,
                    url: URL(string: "https://history.example/failed?safe=visible")!,
                    receivedAt: Date(),
                    source: .unknown,
                    state: .presenting,
                    attemptCount: 1,
                    lastAttemptedBrowserID: BrowserID("invalid.prism.fixture.browser")
                ),
            ],
            terminalRecords: []
        )
    }

    private static func historyEntry(
        id: UUID,
        url: URL?,
        result: HistoryResult,
        targetName: String?,
        method: RoutingMethod?,
        failureReason: String? = nil
    ) -> HistoryEntry {
        HistoryEntry(
            id: id,
            requestID: id,
            sanitizedURL: url,
            sourceBundleIdentifier: nil,
            sourceDisplayName: "Fixture Source",
            targetBrowserID: targetName == nil ? nil : BrowserID("invalid.prism.fixture.browser"),
            targetDisplayName: targetName,
            method: method,
            result: result,
            matchingRuleID: nil,
            failureReason: failureReason,
            attemptCount: result == .failure ? 1 : 0,
            createdAt: Date(),
            completedAt: Date()
        )
    }
}

@MainActor
private final class DebugHistoryLoadFailingRepository: HistoryRepository {
    private enum Failure: Error { case unavailable }

    func upsert(_: HistoryEntry) throws { throw Failure.unavailable }
    func upsertAndEnforceRetention(_: HistoryEntry, limit _: Int, cutoff _: Date) throws {
        throw Failure.unavailable
    }
    func recent(limit _: Int, newerThan _: Date) throws -> [HistoryEntry] { throw Failure.unavailable }
    func delete(id _: UUID) throws { throw Failure.unavailable }
    func clear() throws { throw Failure.unavailable }
    func enforceRetention(limit _: Int, cutoff _: Date) throws { throw Failure.unavailable }
}

@MainActor
private final class DebugAppDefaultHandlerClient: DefaultHandlerClient {
    private let recorder: DebugUITestEffectRecorder
    private var handlers: [String: String]

    init(recorder: DebugUITestEffectRecorder, initialHandlers: [String: String]) {
        self.recorder = recorder
        handlers = initialHandlers
    }

    func handlerBundleIdentifier(forScheme scheme: String) -> String? {
        recorder.recordDefaultHandlerRead()
        return handlers[scheme]
    }

    func setDefault(applicationURL _: URL, forScheme scheme: String) async throws {
        recorder.recordDefaultHandlerWrite()
        handlers[scheme] = "com.prism.app"
    }
}

@MainActor
private final class DebugAppBrowserCatalog: BrowserCataloging {
    private let browsers: [BrowserDescriptor]
    private let recorder: DebugUITestEffectRecorder

    init(browsers: [BrowserDescriptor], recorder: DebugUITestEffectRecorder) {
        self.browsers = browsers
        self.recorder = recorder
    }

    func scan() async throws -> [BrowserDescriptor] {
        recorder.recordBrowserScan()
        return browsers
    }
}

@MainActor
private final class DebugAppBrowserLauncher: BrowserLaunching {
    private let recorder: DebugUITestEffectRecorder
    private let rejectsHandoff: Bool

    init(recorder: DebugUITestEffectRecorder, rejectsHandoff: Bool) {
        self.recorder = recorder
        self.rejectsHandoff = rejectsHandoff
    }

    func open(_: URL, with _: BrowserDescriptor) async throws -> BrowserLaunchResult {
        recorder.recordBrowserHandoff()
        if rejectsHandoff {
            throw BrowserLaunchError.rejected
        }
        return .handoffSucceeded
    }
}

@MainActor
private final class DebugAppSourceAttributor: SourceAttributing {
    func resolve(senderPID _: Int32?, lastActivated _: SourceApplication?) -> SourceApplication {
        .unknown
    }
}

@MainActor
private final class DebugAppLoginItemClient: LoginItemClient {
    private var currentStatus: LoginItemClientStatus = .notRegistered

    func status() -> LoginItemClientStatus { currentStatus }
    func register() throws { currentStatus = .enabled }
    func unregister() throws { currentStatus = .notRegistered }
    func openSystemSettingsLoginItems() {}
}

@MainActor
private final class DebugAppActivationObserver: ApplicationActivationObserving {
    private let recorder: DebugUITestEffectRecorder
    private let token = NSObject()

    init(recorder: DebugUITestEffectRecorder) {
        self.recorder = recorder
    }

    func observeActivations(
        _ handler: @escaping @MainActor @Sendable (SourceApplication?) -> Void
    ) -> NSObjectProtocol {
        recorder.recordFixtureActivationObserverRegistration()
        return token
    }

    func removeObserver(_: NSObjectProtocol) {}
}

@MainActor
private final class DebugAppIconProvider: ApplicationIconProviding {
    func icon(for _: URL) -> NSImage { NSImage() }
    func icon(bundleIdentifier _: String) -> NSImage? { nil }
}
#endif
