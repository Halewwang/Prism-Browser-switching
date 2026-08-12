#if DEBUG
import AppKit
import Foundation
import PrismCore

enum DebugAppFixtureVariant: String, CaseIterable, Equatable, Sendable {
    case onboarding
    case partialHandler = "partial-handler"
    case emptyBrowsers = "empty-browsers"
    case launchFailure = "launch-failure"
    case onboardingRecovery = "onboarding-recovery"
    case shell
    case recovery

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
final class DebugAppFixtureActivationAnchor {
    private final class ActivationWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private let window: NSWindow

    init() {
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
        NSApp.activate()
    }

    func deactivate() {
        window.orderOut(nil)
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
        let browser = BrowserDescriptor(
            id: BrowserID("invalid.prism.fixture.browser"),
            bundleIdentifier: "invalid.prism.fixture.browser",
            displayName: "Fixture Browser",
            applicationURL: URL(fileURLWithPath: "/Applications/PrismFixtureBrowser.app"),
            securityScopedBookmark: nil,
            origin: .system,
            availability: .available,
            selectorOrder: 0
        )
        let browsers = variant == .emptyBrowsers ? [] : [browser]
        let catalog = DebugAppBrowserCatalog(browsers: browsers, recorder: recorder)
        let settingsRepository = InMemorySettingsRepository()
        if variant == .shell {
            var settings = AppSettings.defaults
            settings.onboardingCompleted = true
            try? settingsRepository.save(settings)
        }
        let environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: InMemoryRuleRepository(),
            historyRepository: InMemoryHistoryRepository(),
            browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
            settingsRepository: settingsRepository
        )
        if variant == .onboardingRecovery {
            environment.present(.corruptStoreRecovered(backupLocation: "/tmp/prism-fixture-backup"))
        }
        let queue = LinkRequestQueue(store: DebugUITestPendingRequestStore(
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
        case .onboarding, .onboardingRecovery, .launchFailure, .shell, .recovery:
            [:]
        case .partialHandler:
            ["http": "com.prism.app"]
        case .emptyBrowsers:
            ["http": "com.prism.app", "https": "com.prism.app"]
        }
    }
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
    func status() -> LoginItemClientStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
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
