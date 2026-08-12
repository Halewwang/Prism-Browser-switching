import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    typealias StatusItemControllerFactory = @MainActor (ProductionAppComposition) -> StatusItemController

    let composition: ProductionAppComposition
    let bootstrapBuffer: BootstrapLinkBuffer
    private let copyCurrentSenderPID: @MainActor () -> Int32?
    private let makeStatusItemController: StatusItemControllerFactory
    private var launchTask: Task<Void, Never>?
    private var statusItemController: StatusItemController?

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
            return
        case .application:
            activateDebugApplicationFixture()
        case .disabled:
            break
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
        guard launchTask == nil else { return }
        let composition = composition
        launchTask = Task { @MainActor in
            await composition.finishLaunchingOnce()
        }
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
    }
#endif
}
