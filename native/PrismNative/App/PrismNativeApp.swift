import SwiftUI

@main
struct PrismNativeApp: App {
    @State private var environment = AppEnvironment.preview

    var body: some Scene {
        WindowGroup(id: "main", for: MainWindowIdentity.self) { _ in
            Text("Prism")
                .frame(minWidth: 760, minHeight: 520)
                .environment(environment)
        } defaultValue: {
            MainWindowIdentity.singleton
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
