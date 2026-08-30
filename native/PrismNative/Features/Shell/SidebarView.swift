import AppKit
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
        VStack(spacing: 0) {
            brandHeader

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
        }
        .frame(
            minWidth: WorkspaceLayout.sidebarMinWidth,
            idealWidth: WorkspaceLayout.sidebarIdealWidth,
            maxWidth: WorkspaceLayout.sidebarMaxWidth
        )
        .background(WorkspaceLayout.sidebarSurface)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            Text("Prism")
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prism")
        .accessibilityIdentifier("appShell.sidebar.brand")
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
