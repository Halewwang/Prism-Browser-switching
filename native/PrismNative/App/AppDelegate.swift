import AppKit
import Carbon
import SwiftUI

private final class MainWindowHostingView: NSHostingView<AnyView> {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    typealias StatusItemControllerFactory = @MainActor (ProductionAppComposition) -> StatusItemController

    let composition: ProductionAppComposition
    let bootstrapBuffer: BootstrapLinkBuffer
    private let copyCurrentSenderPID: @MainActor () -> Int32?
    private let makeStatusItemController: StatusItemControllerFactory
    private var launchTask: Task<Void, Never>?
    private var statusItemController: StatusItemController?
    private var mainWindow: NSWindow?

    var retainedStatusItemController: StatusItemController? {
        statusItemController
    }

#if DEBUG
    let sourceProbeRecorder: SourceProbeRecorder
    let debugUITestMode: DebugUITestMode
    let debugUITestRecorder: DebugUITestEffectRecorder?
    private var debugSelectorHarness: DebugSelectorHarness?
    private var debugApplicationActivationAnchor: DebugAppFixtureActivationAnchor?
#endif

    var environment: AppEnvironment {
        composition.environment
    }

    override init() {
        let buffer = BootstrapLinkBuffer()
#if DEBUG
        let recorder = SourceProbeRecorder.makeDefault()
        sourceProbeRecorder = recorder
        let UItestMode = DebugUITestConfiguration.mode
        debugUITestMode = UItestMode
        if UItestMode.isUITesting {
            let fixture = DebugAppFixture.make(
                bootstrapBuffer: buffer,
                variant: .parse(arguments: ProcessInfo.processInfo.arguments)
            )
            composition = fixture.composition
            debugUITestRecorder = fixture.recorder
        } else {
            composition = ProductionAppComposition.make(
                bootstrapBuffer: buffer,
                diagnosticRecorder: { [weak recorder] diagnostic in
                    recorder?.record(diagnostic)
                }
            )
            debugUITestRecorder = nil
        }
#else
        composition = ProductionAppComposition.make(bootstrapBuffer: buffer)
#endif
        bootstrapBuffer = buffer
        copyCurrentSenderPID = AppleEventSenderReader.copyCurrentSenderPID
        makeStatusItemController = Self.makeProductionStatusItemController
        super.init()
        configureMainWindowOpening()
#if DEBUG
        if debugUITestMode == .application || debugUITestMode == .malformedSelector {
            activateDebugApplicationFixture()
        }
#endif
    }

    init(
        composition: ProductionAppComposition,
        copyCurrentSenderPID: @escaping @MainActor () -> Int32?,
        makeStatusItemController: @escaping StatusItemControllerFactory = { composition in
            AppDelegate.makeProductionStatusItemController(composition: composition)
        }
    ) {
        self.composition = composition
        bootstrapBuffer = composition.bootstrapBuffer
        self.copyCurrentSenderPID = copyCurrentSenderPID
        self.makeStatusItemController = makeStatusItemController
#if DEBUG
        sourceProbeRecorder = SourceProbeRecorder.makeDefault()
        debugUITestMode = .disabled
        debugUITestRecorder = nil
#endif
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        installGetURLHandler()
    }

    private func installGetURLHandler() {
#if DEBUG
        guard !DebugUITestConfiguration.isEnabled else { return }
#endif
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
#if DEBUG
        guard !DebugUITestConfiguration.isEnabled else { return }
#endif
        let senderPID = AppleEventSenderReader.copySenderPID(from: event)
        // The registered handler owns this event; AppKit does not also deliver it
        // to application(_:open:). Each event is a separate click, even for one URL.
        for url in GetURLEvent.urls(in: event) where BootstrapLinkBuffer.accepts(url) {
            composition.linkIntakeService.capture(url: url, senderPID: senderPID)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
#if DEBUG
        guard !DebugUITestConfiguration.isEnabled else { return }
#endif
        let senderPID = copyCurrentSenderPID()
        for url in urls where BootstrapLinkBuffer.accepts(url) {
            composition.linkIntakeService.capture(url: url, senderPID: senderPID)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        switch debugUITestMode {
        case .selector:
            presentDebugSelectorHarness()
            return
        case .malformedSelector:
            activateDebugApplicationFixture()
            showMainWindow()
            return
        case .application:
            activateDebugApplicationFixture()
            showMainWindow()
        case .disabled:
            if ProcessInfo.processInfo.arguments.contains("--source-probe") {
                showMainWindow()
            }
        }
#endif
        if statusItemController == nil {
#if DEBUG
            if debugUITestMode == .application {
                statusItemController = makeDebugStatusItemController()
            } else {
                statusItemController = makeStatusItemController(composition)
            }
#else
            statusItemController = makeStatusItemController(composition)
#endif
        }
        guard launchTask == nil else {
            installGetURLHandler()
            return
        }
        let composition = composition
        launchTask = Task { @MainActor in
            await composition.finishLaunchingOnce()
        }
        installGetURLHandler()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
#if DEBUG
        if debugUITestMode == .application || debugUITestMode == .malformedSelector {
            activateDebugApplicationFixture()
        }
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        composition.activationTracker.stop()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else { return true }
        composition.mainWindowOpening.open(route: environment.route)
        return true
    }

    private static func makeProductionStatusItemController(
        composition: ProductionAppComposition
    ) -> StatusItemController {
        StatusItemController(
            mainWindowOpening: composition.mainWindowOpening,
            environment: composition.environment,
            updateChecker: composition.environment.updateChecker
        )
    }

    private func configureMainWindowOpening() {
        composition.mainWindowOpening.register { [weak self] _, _ in
            self?.showMainWindow()
        }
    }

    private func showMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            return
        }

        let lockedWidth = WorkspaceLayout.windowContentWidth
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: lockedWidth, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Prism"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .windowBackgroundColor
        window.toolbar = nil
        window.contentMinSize = NSSize(width: lockedWidth, height: 640)
        window.contentMaxSize = NSSize(width: lockedWidth, height: 10_000)
        window.isReleasedWhenClosed = false
        let hostingView = MainWindowHostingView(rootView: mainWindowRoot())
        window.contentView = hostingView
        window.center()
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    private func mainWindowRoot() -> AnyView {
#if DEBUG
        switch debugUITestMode {
        case .application:
            return AnyView(
                AppRootView(composition: composition, systemActions: .inert)
                    .preferredColorScheme(DebugApplicationFixtureAppearance.current()?.colorScheme)
                    .onAppear { [weak self] in
                        self?.finishDebugApplicationFixtureActivation()
                    }
            )
        case .malformedSelector:
            return AnyView(
                Text("Invalid UI test configuration")
                    .frame(minWidth: 760, minHeight: 520)
                    .accessibilityIdentifier("uiTest.configurationError")
            )
        case .disabled where ProcessInfo.processInfo.arguments.contains("--source-probe"):
            return AnyView(
                SourceProbeView(recorder: sourceProbeRecorder)
                    .environment(environment)
            )
        case .selector, .disabled:
            break
        }
#endif
        return AnyView(AppRootView(composition: composition))
    }

#if DEBUG
    private func makeDebugStatusItemController() -> StatusItemController? {
        guard let debugUITestRecorder else { return nil }
        return StatusItemController(
            host: DebugNoopStatusItemHost(recorder: debugUITestRecorder),
            mainWindowOpening: composition.mainWindowOpening,
            environment: composition.environment,
            updateChecker: composition.environment.updateChecker,
            terminate: {}
        )
    }

    func presentDebugSelectorHarness() {
        guard let variant = DebugUITestConfiguration.selectorVariant,
              let appearance = DebugUITestConfiguration.selectorAppearance
        else { return }
        if debugSelectorHarness == nil {
            debugSelectorHarness = DebugSelectorHarness(variant: variant, appearance: appearance)
        }
        debugSelectorHarness?.present()
    }

    func activateDebugApplicationFixture() {
        if debugApplicationActivationAnchor == nil {
            debugApplicationActivationAnchor = DebugAppFixtureActivationAnchor()
        }
        debugApplicationActivationAnchor?.activate()
    }

    func finishDebugApplicationFixtureActivation() {
        debugApplicationActivationAnchor?.deactivate()
        debugApplicationActivationAnchor = nil
        _ = NSRunningApplication.current.activate(
            options: DebugAppFixtureActivationAnchor.foregroundActivationOptions
        )
    }
#endif
}
