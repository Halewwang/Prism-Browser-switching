import SwiftUI

struct AppShellDestination: Identifiable, Equatable {
    let route: AppRoute
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String

    var id: AppRoute { route }

    static let all: [AppShellDestination] = [
        AppShellDestination(
            route: .history,
            title: "History",
            systemImage: "clock.arrow.circlepath",
            accessibilityIdentifier: "appShell.sidebar.history"
        ),
        AppShellDestination(
            route: .rules,
            title: "Rules",
            systemImage: "list.bullet.rectangle",
            accessibilityIdentifier: "appShell.sidebar.rules"
        ),
        AppShellDestination(
            route: .browsers,
            title: "Browsers",
            systemImage: "safari",
            accessibilityIdentifier: "appShell.sidebar.browsers"
        ),
        AppShellDestination(
            route: .settings,
            title: "Settings",
            systemImage: "gearshape",
            accessibilityIdentifier: "appShell.sidebar.settings"
        ),
    ]

    static func destination(for route: AppRoute) -> AppShellDestination {
        all.first { $0.route == route } ?? all[0]
    }
}

struct SidebarView: View {
    @Binding var selection: AppRoute

    var body: some View {
        List(selection: optionalSelection) {
            ForEach(AppShellDestination.all) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination.route)
                    .accessibilityIdentifier(destination.accessibilityIdentifier)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Prism")
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var optionalSelection: Binding<AppRoute?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else { return }
                selection = newValue
            }
        )
    }
}
