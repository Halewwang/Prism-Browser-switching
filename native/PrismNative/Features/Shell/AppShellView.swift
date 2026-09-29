import SwiftUI

enum WorkspaceLayout {
    static let contentInset: CGFloat = 36
    static let headerVerticalInset: CGFloat = 28
    static let pageTitleFont = Font.system(size: 27, weight: .semibold)
    static let sidebarSurface = SettingsPalette.sidebar
    static let contentSurface = SettingsPalette.canvas
    static let windowContentWidth: CGFloat = 1120
    static let sidebarWidth: CGFloat = 218
}

enum AppShellActionID: String, CaseIterable, Equatable, Sendable {
    case testLink
    case openApplicationsFolder
    case openDefaultAppsSettings
    case restart
}

@MainActor
struct AppShellActions {
    private let testLink: () -> Void
    private let openApplicationsFolder: () -> Void
    private let openDefaultAppsSettings: () -> Void
    private let restart: () -> Void

    init(
        testLink: @escaping () -> Void = {},
        openApplicationsFolder: @escaping () -> Void = {},
        openDefaultAppsSettings: @escaping () -> Void = {},
        restart: @escaping () -> Void = {}
    ) {
        self.testLink = testLink
        self.openApplicationsFolder = openApplicationsFolder
        self.openDefaultAppsSettings = openDefaultAppsSettings
        self.restart = restart
    }

    func perform(_ action: AppShellActionID) {
        switch action {
        case .testLink:
            testLink()
        case .openApplicationsFolder:
            openApplicationsFolder()
        case .openDefaultAppsSettings:
            openDefaultAppsSettings()
        case .restart:
            restart()
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
        addCustomBrowser: @escaping @MainActor () async -> OnboardingCustomBrowserResult = { .cancelled },
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
        HStack(spacing: 0) {
            SidebarView(selection: $route)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: WorkspaceLayout.windowContentWidth,
            maxWidth: WorkspaceLayout.windowContentWidth,
            minHeight: 640
        )
        .tint(SettingsPalette.primary)
        .background(WorkspaceLayout.contentSurface)
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
                RulesManagementView(browserCatalog: browserCatalog, onOpenSettings: { route = .settings })
            } else if route == .settings {
                SettingsManagementView(
                    browserCatalog: browserCatalog,
                    addCustomBrowser: addCustomBrowser,
                    openDefaultAppsSettings: { actions.perform(.openDefaultAppsSettings) },
                    restart: { actions.perform(.restart) }
                )
            } else {
                PageStateView(model: AppShellPresentation.historyFallback) { rawAction in
                    guard let action = AppShellActionID(rawValue: rawAction) else { return }
                    actions.perform(action)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            WorkspaceLayout.contentSurface
                .ignoresSafeArea(edges: .top)
        }
    }
}
