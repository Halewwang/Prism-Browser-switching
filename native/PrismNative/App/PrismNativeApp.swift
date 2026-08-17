import SwiftUI

@main
struct PrismNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main", for: MainWindowIdentity.self) { _ in
            MainWindowRoot(mainWindowOpening: appDelegate.composition.mainWindowOpening) {
#if DEBUG
                switch DebugUITestConfiguration.mode {
                case .selector:
                    DebugSelectorHarnessBootstrapView(appDelegate: appDelegate)
                case .malformedSelector:
                    Text("Invalid UI test configuration")
                        .frame(minWidth: 760, minHeight: 520)
                        .accessibilityIdentifier("uiTest.configurationError")
                case .application:
                    DebugApplicationFixtureBootstrapView(appDelegate: appDelegate)
                case .disabled:
                    if ProcessInfo.processInfo.arguments.contains("--source-probe") {
                        SourceProbeView(recorder: appDelegate.sourceProbeRecorder)
                            .environment(appDelegate.environment)
                    } else {
                        mainRoot
                    }
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
        AppRootView(composition: appDelegate.composition)
    }
}

#if DEBUG
private struct DebugApplicationFixtureBootstrapView: View {
    let appDelegate: AppDelegate

    var body: some View {
        AppRootView(
            composition: appDelegate.composition,
            systemActions: .inert
        )
        .preferredColorScheme(DebugApplicationFixtureAppearance.current()?.colorScheme)
        .onAppear {
            appDelegate.finishDebugApplicationFixtureActivation()
        }
    }
}
#endif

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
