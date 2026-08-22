#if DEBUG
import AppKit
import PrismCore
import SwiftUI

enum DebugUITestMode: Equatable {
    case disabled
    case application
    case selector(
        variant: DebugUITestConfiguration.SelectorVariant,
        appearance: DebugUITestConfiguration.SelectorAppearance,
        captureURL: URL?
    )
    case malformedSelector

    var isUITesting: Bool {
        self != .disabled
    }

    var blocksNormalLaunch: Bool {
        switch self {
        case .selector, .malformedSelector:
            true
        case .disabled, .application:
            false
        }
    }

    var mayInstallSystemStatusItem: Bool {
        self == .disabled
    }

    var mayUseSystemServices: Bool {
        self == .disabled
    }
}

enum DebugUITestConfiguration {
    enum SelectorVariant: String {
        case three
        case five
        case failed
        case empty
        case recovery

        var browserCount: Int {
            switch self {
            case .three: 3
            case .five: 5
            case .failed, .recovery: 3
            case .empty: 0
            }
        }

        func presentationContext(firstBrowserID: BrowserID?) -> SelectorPresentationContext {
            switch self {
            case .three, .five:
                .normal
            case .failed:
                .launchFailed(
                    browserID: firstBrowserID ?? BrowserID("selector-fixture-1"),
                    message: "Harness launch failed"
                )
            case .empty:
                .noAvailableBrowsers
            case .recovery:
                .outcomeUnknown(browserID: firstBrowserID)
            }
        }
    }

    enum SelectorAppearance: String {
        case light
        case dark

        var nsAppearance: NSAppearance {
            NSAppearance(named: self == .dark ? .darkAqua : .aqua)!
        }
    }

    static var mode: DebugUITestMode {
        parse(arguments: ProcessInfo.processInfo.arguments)
    }

    static var isEnabled: Bool {
        mode.isUITesting
    }

    static var selectorVariant: SelectorVariant? {
        guard case let .selector(variant, _, _) = mode else { return nil }
        return variant
    }

    static var selectorAppearance: SelectorAppearance? {
        guard case let .selector(_, appearance, _) = mode else { return nil }
        return appearance
    }

    static var selectorCaptureURL: URL? {
        guard case let .selector(_, _, captureURL) = mode else { return nil }
        return captureURL
    }

    static func parse(arguments: [String]) -> DebugUITestMode {
        guard arguments.contains("--ui-testing") else { return .disabled }
        guard arguments.contains("--selector-harness") else { return .application }

        guard let variantValue = value(after: "--selector-harness", in: arguments),
              let variant = SelectorVariant(rawValue: variantValue),
              let appearanceValue = value(after: "--selector-appearance", in: arguments),
              let appearance = SelectorAppearance(rawValue: appearanceValue)
        else {
            return .malformedSelector
        }

        var captureURL: URL?
        if arguments.contains("--selector-capture-path") {
            guard let capturePath = value(after: "--selector-capture-path", in: arguments),
                  let validatedCaptureURL = validatedCaptureURL(path: capturePath)
            else {
                return .malformedSelector
            }
            captureURL = validatedCaptureURL
        }

        return .selector(
            variant: variant,
            appearance: appearance,
            captureURL: captureURL
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: flag),
              arguments.indices.contains(flagIndex + 1)
        else { return nil }
        let value = arguments[flagIndex + 1]
        return value.hasPrefix("--") ? nil : value
    }

    private static func validatedCaptureURL(path: String) -> URL? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL
        let isAppTemporaryFile = url.path.hasPrefix(temporaryDirectory.path + "/")
        let isSharedTestCapture = url.path.hasPrefix("/tmp/prism-selector-")
        guard isAppTemporaryFile || isSharedTestCapture else { return nil }
        return url
    }
}

actor DebugUITestPendingRequestStore: PendingRequestStore, PersistenceWarningSource {
    private var snapshot: PendingRequestSnapshot
    private let failsLoad: Bool

    init(
        initialSnapshot: PendingRequestSnapshot = .init(pendingRequests: [], terminalRecords: []),
        failsLoad: Bool = false
    ) {
        snapshot = initialSnapshot
        self.failsLoad = failsLoad
    }

    func load() async throws -> PendingRequestSnapshot {
        if failsLoad {
            throw DebugUITestPendingRequestStoreError.unavailable
        }
        return snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        self.snapshot = snapshot
    }

    func drainPersistenceWarnings() async -> [PersistenceWarning] {
        []
    }
}

private enum DebugUITestPendingRequestStoreError: Error {
    case unavailable
}

struct DebugSelectorHarnessBootstrapView: View {
    let appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .onAppear {
                appDelegate.presentDebugSelectorHarness()
            }
    }
}

@MainActor
final class DebugSelectorHarness {
    private final class ActivationWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private let coordinator: WindowCoordinator
    private let presentationContext: SelectorPresentationContext
    private let activationWindow: NSWindow
    private let selectorPanel: SelectorPanel
    private var didPresent = false

    init(
        variant: DebugUITestConfiguration.SelectorVariant,
        appearance: DebugUITestConfiguration.SelectorAppearance
    ) {
        let browsers = Self.makeBrowsers(count: variant.browserCount)
        presentationContext = variant.presentationContext(firstBrowserID: browsers.first?.id)
        let routing = DebugSelectorRoutingCoordinator()
        let contentProvider = DebugSelectorContentProvider(
            browsers: browsers,
            routingCoordinator: routing
        )
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let desiredOrigin = CGPoint(
            x: visibleFrame.midX - SelectorPanel.contentSize.width / 2,
            y: visibleFrame.midY - SelectorPanel.contentSize.height / 2
        )
        let panel = SelectorPanel(
            contentRect: CGRect(origin: desiredOrigin, size: SelectorPanel.contentSize)
        )
        panel.appearance = appearance.nsAppearance
        selectorPanel = panel
        let activationWindow = ActivationWindow(
            contentRect: CGRect(origin: desiredOrigin, size: SelectorPanel.contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        activationWindow.isOpaque = false
        activationWindow.backgroundColor = .clear
        activationWindow.hasShadow = false
        activationWindow.ignoresMouseEvents = true
        activationWindow.alphaValue = 0.01
        activationWindow.setAccessibilityElement(false)
        self.activationWindow = activationWindow
        coordinator = WindowCoordinator(
            mainWindowOpening: MainWindowOpening(updateRoute: { _ in }),
            panelController: SelectorPanelController(panel: panel),
            pointerLocation: {
                CGPoint(
                    x: desiredOrigin.x - 12,
                    y: desiredOrigin.y + SelectorPanel.contentSize.height + 12
                )
            },
            visibleFrames: { [visibleFrame] },
            contentProvider: contentProvider
        )
        routing.presenter = coordinator
    }

    func present() {
        guard !didPresent else { return }
        didPresent = true
        NSApp.setActivationPolicy(.regular)
        activationWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
        let request = LinkRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000711")!,
            url: URL(string: "https://selector.invalid/example")!,
            receivedAt: Date(timeIntervalSince1970: 711),
            source: SourceApplication(
                bundleIdentifier: nil,
                displayName: "Test Source",
                confidence: .unknown
            ),
            state: .presenting
        )
        coordinator.present(request, context: presentationContext)
        if let captureURL = DebugUITestConfiguration.selectorCaptureURL {
            DispatchQueue.main.async { [weak selectorPanel] in
                guard let view = selectorPanel?.contentView else { return }
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: representation)
                guard let data = representation.representation(using: .png, properties: [:]) else { return }
                try? data.write(to: captureURL, options: .atomic)
            }
        }
    }

    private static func makeBrowsers(count: Int) -> [BrowserDescriptor] {
        (0 ..< count).map { index in
            BrowserDescriptor(
                id: BrowserID("selector-fixture-\(index + 1)"),
                bundleIdentifier: "invalid.selector.fixture.\(index + 1)",
                displayName: "Harness Browser \(index + 1)",
                applicationURL: URL(fileURLWithPath: "/Applications/SelectorFixture\(index + 1).app"),
                securityScopedBookmark: nil,
                origin: .system,
                availability: .available,
                selectorOrder: index
            )
        }
    }
}

@MainActor
private final class DebugSelectorContentProvider: SelectorContentProviding {
    private let browsers: [BrowserDescriptor]
    private let routingCoordinator: any LinkRoutingCoordinating
    private let catalog: DebugSelectorBrowserCatalog
    private let pendingCountProvider = DebugSelectorPendingCountProvider()
    private let navigationHandler = DebugSelectorNavigationHandler()
    private let iconProvider = DebugSelectorIconProvider()

    init(
        browsers: [BrowserDescriptor],
        routingCoordinator: any LinkRoutingCoordinating
    ) {
        self.browsers = browsers
        self.routingCoordinator = routingCoordinator
        catalog = DebugSelectorBrowserCatalog(browsers: browsers)
    }

    func makeSession(request: LinkRequest, context: SelectorPresentationContext) -> SelectorSession {
        let model = SelectorViewModel(
            request: request,
            context: context,
            browsers: browsers,
            browserCatalog: catalog,
            routingCoordinator: routingCoordinator,
            pendingCountProvider: pendingCountProvider,
            navigationHandler: navigationHandler,
            eligibleSourceBundleIDs: []
        )
        let monitoringTask = model.startPendingCountMonitoring()
        return SelectorSession(
            requestID: request.id,
            content: AnyView(SelectorView(model: model, iconProvider: iconProvider)),
            monitoringTask: monitoringTask,
            cancelAction: { [weak model] in
                model?.stopPendingCountMonitoring()
            }
        )
    }
}

@MainActor
private final class DebugSelectorRoutingCoordinator: LinkRoutingCoordinating {
    weak var presenter: (any LinkSelectionPresenting)?

    func processNext(
        while _: @escaping @MainActor () -> Bool
    ) async -> LinkRoutingPassDisposition {
        .drained
    }

    func select(browserID _: BrowserID, for requestID: UUID) async {
        presenter?.dismiss(requestID: requestID)
    }

    func retry(browserID _: BrowserID, for _: UUID) async {}

    func markUncertainAttemptCompleted(requestID _: UUID) async {}

    func cancel(requestID: UUID) async {
        presenter?.dismiss(requestID: requestID)
    }
}

@MainActor
private final class DebugSelectorBrowserCatalog: BrowserCataloging {
    private let browsers: [BrowserDescriptor]

    init(browsers: [BrowserDescriptor]) {
        self.browsers = browsers
    }

    func scan() async throws -> [BrowserDescriptor] {
        browsers
    }
}

@MainActor
private final class DebugSelectorPendingCountProvider: SelectorPendingCountProviding {
    func pendingCountUpdates() async -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream<Int>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.yield(1)
        return stream
    }
}

@MainActor
private final class DebugSelectorNavigationHandler: SelectorNavigationHandling {
    func openBrowserManagement() {}
    func openRuleEditor(prefill _: SelectorRulePrefill) {}
}

@MainActor
private final class DebugSelectorIconProvider: ApplicationIconProviding {
    func icon(for _: URL) -> NSImage {
        NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
    }

    func icon(bundleIdentifier _: String) -> NSImage? {
        nil
    }
}
#endif
