import SwiftUI

@main
struct PrismNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main", for: MainWindowIdentity.self) { _ in
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--source-probe") {
                SourceProbeView(recorder: appDelegate.sourceProbeRecorder)
                    .environment(appDelegate.environment)
            } else {
                mainRoot
            }
#else
            mainRoot
#endif
        } defaultValue: {
            MainWindowIdentity.singleton
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    private var mainRoot: some View {
        Text("Prism")
            .frame(minWidth: 760, minHeight: 520)
            .environment(appDelegate.environment)
    }
}
