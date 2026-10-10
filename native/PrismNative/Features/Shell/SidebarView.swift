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
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selection: AppRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            brandHeader
            VStack(spacing: 7) {
                ForEach(AppShellDestination.all) { destination in
                    Button {
                        selection = destination.route
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: destination.systemImage)
                                .font(.system(size: 17, weight: .regular))
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text(LocalizedStringKey(destination.title))
                                .font(.system(size: 15, weight: selection == destination.route ? .semibold : .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(selection == destination.route ? SettingsPalette.primary : SettingsPalette.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background {
                            if selection == destination.route {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(SettingsPalette.group)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsPalette.border, lineWidth: 1))
                                    .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(destination.accessibilityIdentifier)
                    .accessibilityValue(selection == destination.route ? "Selected" : "")
                }
            }
            Spacer(minLength: 24)
            runtimeStatus
        }
        .padding(.horizontal, 14)
        .padding(.top, 60)
        .padding(.bottom, 20)
        .frame(width: WorkspaceLayout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background {
            (reduceTransparency ? SettingsPalette.window : WorkspaceLayout.sidebarSurface).ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(SettingsPalette.border).frame(width: 1)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Prism")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(SettingsPalette.primary)
                    .frame(height: 30, alignment: .leading)
                Text("Your links, in the right place")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.tertiary)
                    .frame(height: 17, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prism")
        .accessibilityIdentifier("appShell.sidebar.brand")
    }

    private var runtimeStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(environment.settings.automaticRulesEnabled ? SettingsPalette.primary : SettingsPalette.secondary)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(environment.settings.automaticRulesEnabled ? "Automatic routing is on" : "Automatic routing is paused")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsPalette.secondary)
                    .frame(height: 19, alignment: .leading)
            }
            Text("Records stay on this Mac")
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.tertiary)
                .frame(height: 17, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsPalette.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("appShell.sidebar.routingStatus")
    }
}
