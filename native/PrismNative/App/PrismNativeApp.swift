import SwiftUI

@main
struct PrismNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Prism") { PrismAboutWindowController.shared.present() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    appDelegate.composition.mainWindowOpening.open(route: .settings)
                }
                .keyboardShortcut(",")
                Button("Manage Browsers") {
                    appDelegate.environment.stageBrowserManagement()
                    appDelegate.composition.mainWindowOpening.open(route: .settings)
                }
            }
        }
    }
}
