import SwiftUI

struct AppShellDestination: Identifiable, Equatable {
    let route: AppRoute
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String

    var id: AppRoute { route }

    static let all: [AppShellDestination] = [
        AppShellDestination(
            route: .overview,
            title: "Overview",
            systemImage: "rectangle.3.group.fill",
            accessibilityIdentifier: "appShell.sidebar.overview"
        ),
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
            Section("Workspace") {
                ForEach(AppShellDestination.all) { destination in
                    Label(destination.title, systemImage: destination.systemImage)
                        .font(.body.weight(.medium))
                        .tag(destination.route)
                        .padding(.vertical, 5)
                        .accessibilityIdentifier(destination.accessibilityIdentifier)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Prism")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
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
