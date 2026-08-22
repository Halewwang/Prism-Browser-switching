import SwiftUI

enum AppShellActionID: String, CaseIterable, Equatable, Sendable {
    case testLink
    case openApplicationsFolder
}

@MainActor
struct AppShellActions {
    private let testLink: () -> Void
    private let openApplicationsFolder: () -> Void

    init(
        testLink: @escaping () -> Void = {},
        openApplicationsFolder: @escaping () -> Void = {}
    ) {
        self.testLink = testLink
        self.openApplicationsFolder = openApplicationsFolder
    }

    func perform(_ action: AppShellActionID) {
        switch action {
        case .testLink:
            testLink()
        case .openApplicationsFolder:
            openApplicationsFolder()
        }
    }
}

enum AppShellPresentation {
    static let historyFallback = PageStateModel.empty(
        iconSystemName: "clock.arrow.circlepath",
        title: "Handled links will appear here",
        message: "Links handled by Prism will appear here with their browser and result.",
        actions: [
            PageStateAction(
                id: AppShellActionID.testLink.rawValue,
                title: "Test Link",
                accessibilityIdentifier: "history.testLink"
            ),
        ]
    )
}

struct AppShellView: View {
    @Binding private var route: AppRoute

    private let actions: AppShellActions
    private let historyModel: HistoryViewModel?
    private let browserCatalog: any BrowserCataloging
    private let addCustomBrowser: @MainActor () async -> OnboardingCustomBrowserResult
    private let recoveryBanner: RecoveryBannerModel?
    private let onRecoveryAction: () -> Void

    init(
        route: Binding<AppRoute>,
        actions: AppShellActions = AppShellActions(),
        historyModel: HistoryViewModel? = nil,
        browserCatalog: any BrowserCataloging,
        addCustomBrowser: @escaping @MainActor () async -> OnboardingCustomBrowserResult,
        recoveryBanner: RecoveryBannerModel? = nil,
        onRecoveryAction: @escaping () -> Void = {}
    ) {
        _route = route
        self.actions = actions
        self.historyModel = historyModel
        self.browserCatalog = browserCatalog
        self.addCustomBrowser = addCustomBrowser
        self.recoveryBanner = recoveryBanner
        self.onRecoveryAction = onRecoveryAction
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $route)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 940, minHeight: 640)
        .tint(.accentColor)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var detail: some View {
        return VStack(spacing: 0) {
            if let recoveryBanner {
                RecoveryBanner(model: recoveryBanner, onAction: onRecoveryAction)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            if route == .history, let historyModel {
                HistoryView(model: historyModel) {
                    actions.perform(.testLink)
                }
            } else if route == .rules {
                RulesManagementView(browserCatalog: browserCatalog)
            } else if route == .browsers {
                BrowsersManagementView(
                    browserCatalog: browserCatalog,
                    addCustomBrowser: addCustomBrowser,
                    openApplicationsFolder: { actions.perform(.openApplicationsFolder) }
                )
            } else if route == .settings {
                SettingsManagementView(browserCatalog: browserCatalog)
            } else {
                PageStateView(model: AppShellPresentation.historyFallback) { rawAction in
                    guard let action = AppShellActionID(rawValue: rawAction) else { return }
                    actions.perform(action)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle(AppShellDestination.destination(for: route).title)
    }
}
