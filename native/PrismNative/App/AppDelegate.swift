import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let composition: ProductionAppComposition
    let bootstrapBuffer: BootstrapLinkBuffer
    private let copyCurrentSenderPID: @MainActor () -> Int32?
    private var launchTask: Task<Void, Never>?

#if DEBUG
    let sourceProbeRecorder: SourceProbeRecorder
    private var debugSelectorHarness: DebugSelectorHarness?
#endif

    var environment: AppEnvironment {
        composition.environment
    }

    override init() {
        let buffer = BootstrapLinkBuffer()
#if DEBUG
        let recorder = SourceProbeRecorder.makeDefault()
        sourceProbeRecorder = recorder
        if DebugUITestConfiguration.isEnabled {
            composition = ProductionAppComposition.makeForTesting(
                bootstrapBuffer: buffer,
                modelContainerFactory: { try ModelContainerFactory.make(inMemory: true) },
                recoveryStoreFactory: { DebugUITestPendingRequestStore() }
            )
        } else {
            composition = ProductionAppComposition.make(
                bootstrapBuffer: buffer,
                diagnosticRecorder: { [weak recorder] diagnostic in
                    recorder?.record(diagnostic)
                }
            )
        }
#else
        composition = ProductionAppComposition.make(bootstrapBuffer: buffer)
#endif
        bootstrapBuffer = buffer
        copyCurrentSenderPID = AppleEventSenderReader.copyCurrentSenderPID
        super.init()
    }

    init(
        composition: ProductionAppComposition,
        copyCurrentSenderPID: @escaping @MainActor () -> Int32?
    ) {
        self.composition = composition
        bootstrapBuffer = composition.bootstrapBuffer
        self.copyCurrentSenderPID = copyCurrentSenderPID
#if DEBUG
        sourceProbeRecorder = SourceProbeRecorder.makeDefault()
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
        if DebugUITestConfiguration.isEnabled {
            presentDebugSelectorHarness()
            return
        }
#endif
        guard launchTask == nil else { return }
        let composition = composition
        launchTask = Task { @MainActor in
            await composition.finishLaunchingOnce()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        composition.activationTracker.stop()
    }

#if DEBUG
    func presentDebugSelectorHarness() {
        guard let variant = DebugUITestConfiguration.selectorVariant,
              let appearance = DebugUITestConfiguration.selectorAppearance
        else { return }
        if debugSelectorHarness == nil {
            debugSelectorHarness = DebugSelectorHarness(variant: variant, appearance: appearance)
        }
        debugSelectorHarness?.present()
    }
#endif
}
