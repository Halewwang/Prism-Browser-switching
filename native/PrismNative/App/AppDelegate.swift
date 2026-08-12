import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let composition: ProductionAppComposition
    let bootstrapBuffer: BootstrapLinkBuffer
    private let copyCurrentSenderPID: @MainActor () -> Int32?
    private var launchTask: Task<Void, Never>?

#if DEBUG
    let sourceProbeRecorder: SourceProbeRecorder
#endif

    var environment: AppEnvironment {
        composition.environment
    }

    override init() {
        let buffer = BootstrapLinkBuffer()
#if DEBUG
        let recorder = SourceProbeRecorder.makeDefault()
        sourceProbeRecorder = recorder
        composition = ProductionAppComposition.make(
            bootstrapBuffer: buffer,
            diagnosticRecorder: { [weak recorder] diagnostic in
                recorder?.record(diagnostic)
            }
        )
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
        let senderPID = copyCurrentSenderPID()
        for url in urls where BootstrapLinkBuffer.accepts(url) {
            composition.linkIntakeService.capture(url: url, senderPID: senderPID)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard launchTask == nil else { return }
        let composition = composition
        launchTask = Task { @MainActor in
            await composition.finishLaunchingOnce()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        composition.activationTracker.stop()
    }
}
