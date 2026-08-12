import SwiftUI

@main
struct PrismNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main", for: MainWindowIdentity.self) { _ in
            MainWindowRoot(mainWindowOpening: appDelegate.composition.mainWindowOpening) {
#if DEBUG
                if DebugUITestConfiguration.selectorVariant != nil {
                    DebugSelectorHarnessBootstrapView(appDelegate: appDelegate)
                } else if ProcessInfo.processInfo.arguments.contains("--source-probe") {
                    SourceProbeView(recorder: appDelegate.sourceProbeRecorder)
                        .environment(appDelegate.environment)
                } else {
                    mainRoot
                }
#else
                mainRoot
#endif
            }
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

private struct MainWindowRoot<Content: View>: View {
    @Environment(\.openWindow) private var openWindow

    let mainWindowOpening: MainWindowOpening
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .onAppear {
                mainWindowOpening.register { id, value in
                    openWindow(id: id, value: value)
                }
            }
    }
}
