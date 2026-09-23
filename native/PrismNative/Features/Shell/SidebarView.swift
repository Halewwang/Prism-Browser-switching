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
            route: .history,
            title: "History",
            systemImage: "clock",
            accessibilityIdentifier: "appShell.sidebar.history"
        ),
        AppShellDestination(
            route: .rules,
            title: "Rules",
            systemImage: "list.bullet",
            accessibilityIdentifier: "appShell.sidebar.rules"
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
                    Label {
                        Text(LocalizedStringKey(destination.title))
                            .font(.system(size: 13, weight: .regular))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: destination.systemImage)
                            .font(.system(size: 13, weight: .light))
                            .frame(width: 16, height: 16)
                    }
                    .tag(destination.route)
                    .padding(.vertical, 2)
                    .accessibilityIdentifier(destination.accessibilityIdentifier)
                }
            }
            .listStyle(.sidebar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
        }
        .frame(width: WorkspaceLayout.sidebarWidth)
        .background {
            WorkspaceLayout.sidebarSurface
                .ignoresSafeArea(edges: .top)
        }
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
        .padding(.horizontal, 14)
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
