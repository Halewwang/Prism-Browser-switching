import SwiftUI

@main
struct PrismNativeApp: App {
    @State private var composition = ProductionAppComposition.make()

    var body: some Scene {
        WindowGroup(id: "main", for: MainWindowIdentity.self) { _ in
            Text("Prism")
                .frame(minWidth: 760, minHeight: 520)
                .environment(composition.environment)
                .task {
                    await composition.restoreOnce()
                }
        } defaultValue: {
            MainWindowIdentity.singleton
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
