import PrismCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging
    let testLink: () -> Void
    let openRoute: (AppRoute) -> Void

    @State private var browserCount: Int?
    @State private var ruleCount = 0
    @State private var linkHandlerState: DefaultHandlerState?
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statusGrid
                quickActions
            }
            .padding(28)
            .frame(maxWidth: 1_080, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task { await refresh() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isReady ? "Prism is ready" : "Finish your Prism setup")
                    .font(.system(size: 28, weight: .bold))
                    .accessibilityIdentifier("appShell.page.overview.heading")
                Text(headerMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            Button("Refresh status", systemImage: "arrow.clockwise") {
                Task { await refresh() }
            }
            .disabled(isRefreshing)
            .accessibilityIdentifier("overview.refresh")
        }
    }

    private var statusGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            OverviewStatusCard(
                title: "Link handling",
                value: linkHandlerValue,
                detail: linkHandlerDetail,
                symbol: linkHandlerState == .active ? "link.circle.fill" : "link.badge.plus",
                tint: linkHandlerState == .active ? .green : .orange,
                accessibilityIdentifier: "overview.linkHandling"
            )
            OverviewStatusCard(
                title: "Automatic rules",
                value: environment.settings.automaticRulesEnabled ? "Active" : "Paused",
                detail: "\(ruleCount) \(ruleCount == 1 ? "rule" : "rules") configured",
                symbol: environment.settings.automaticRulesEnabled ? "checkmark.circle.fill" : "pause.circle.fill",
                tint: environment.settings.automaticRulesEnabled ? .green : .orange,
                accessibilityIdentifier: "overview.automaticRules"
            )
            OverviewStatusCard(
                title: "Available browsers",
                value: browserCount.map { "\($0) ready" } ?? "Checking…",
                detail: "Selector order is managed in Browsers",
                symbol: "safari.fill",
                tint: browserCount == 0 ? .orange : .accentColor,
                accessibilityIdentifier: "overview.browsers"
            )
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick actions")
                .font(.headline)
            HStack(spacing: 10) {
                Button("Test Link", systemImage: "link") {
                    testLink()
                }
                .buttonStyle(.borderedProminent)
                .disabled(browserCount == 0 || isRefreshing)
                .accessibilityIdentifier("overview.testLink")

                Button("Manage Rules", systemImage: "list.bullet.rectangle") {
                    openRoute(.rules)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("overview.manageRules")

                Button("Manage Browsers", systemImage: "safari") {
                    openRoute(.browsers)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("overview.manageBrowsers")

                Button("Review Link Handling", systemImage: "gearshape") {
                    openRoute(.settings)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("overview.openSettings")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private var isReady: Bool {
        linkHandlerState == .active && (browserCount ?? 0) > 0
    }

    private var headerMessage: String {
        if linkHandlerState != .active {
            return "Review default web-link handling so Prism can receive both HTTP and HTTPS links."
        }
        if browserCount == 0 {
            return "Add a browser before routing links."
        }
        return "Your routing controls and recent link activity are ready when you need them."
    }

    private var linkHandlerValue: String {
        linkHandlerState == .active ? "HTTP + HTTPS active" : "Needs attention"
    }

    private var linkHandlerDetail: String {
        guard case let .some(.inactive(http, https)) = linkHandlerState else {
            return linkHandlerState == nil ? "Checking your default handler" : "Prism receives both web-link schemes"
        }
        let inactiveSchemes = [http ? nil : "HTTP", https ? nil : "HTTPS"].compactMap { $0 }
        return "Set Prism as default for \(inactiveSchemes.joined(separator: " and "))"
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        browserCount = (try? await browserCatalog.scan())?.filter { $0.availability == .available }.count
        ruleCount = (try? environment.ruleRepository.all())?.count ?? 0
        if let defaultBrowserService = environment.defaultBrowserService {
            linkHandlerState = try? await defaultBrowserService.status()
        } else {
            linkHandlerState = nil
        }
    }
}

private struct OverviewStatusCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
