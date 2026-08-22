import SwiftUI

struct AppShellDestination: Identifiable {
    let route: AppRoute
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String

    var id: AppRoute { route }

    static let all: [AppShellDestination] = [
        AppShellDestination(
            route: .overview,
            title: "Overview",
            systemImage: "square.grid.2x2",
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

}

struct SidebarView: View {
    @Binding var selection: AppRoute

    var body: some View {
        List(selection: optionalSelection) {
            ForEach(AppShellDestination.all) { destination in
                Label(LocalizedStringKey(destination.title), systemImage: destination.systemImage)
                    .font(.body.weight(.medium))
                    .tag(destination.route)
                    .padding(.vertical, 7)
                    .accessibilityIdentifier(destination.accessibilityIdentifier)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 228, ideal: 248, max: 300)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .padding(.top, 14)
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
