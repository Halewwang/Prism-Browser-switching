import SwiftUI

enum AppShellActionID: String, CaseIterable, Equatable, Sendable {
    case testLink
    case createRule
    case clearRuleSearch
    case rescan
    case addCustomBrowser
    case openApplicationsFolder
}

@MainActor
struct AppShellActions {
    private let testLink: () -> Void
    private let createRule: () -> Void
    private let clearRuleSearch: () -> Void
    private let rescan: () -> Void
    private let addCustomBrowser: () -> Void
    private let openApplicationsFolder: () -> Void

    init(
        testLink: @escaping () -> Void = {},
        createRule: @escaping () -> Void = {},
        clearRuleSearch: @escaping () -> Void = {},
        rescan: @escaping () -> Void = {},
        addCustomBrowser: @escaping () -> Void = {},
        openApplicationsFolder: @escaping () -> Void = {}
    ) {
        self.testLink = testLink
        self.createRule = createRule
        self.clearRuleSearch = clearRuleSearch
        self.rescan = rescan
        self.addCustomBrowser = addCustomBrowser
        self.openApplicationsFolder = openApplicationsFolder
    }

    func perform(_ action: AppShellActionID) {
        switch action {
        case .testLink:
            testLink()
        case .createRule:
            createRule()
        case .clearRuleSearch:
            clearRuleSearch()
        case .rescan:
            rescan()
        case .addCustomBrowser:
            addCustomBrowser()
        case .openApplicationsFolder:
            openApplicationsFolder()
        }
    }
}

enum RulesShellState: Equatable, Sendable {
    case empty
    case noSearchResults
}

struct AppShellPage: Equatable, Sendable {
    let accessibilityIdentifier: String
    let state: PageStateModel
}

struct AppShellPresentation: Equatable, Sendable {
    var rulesState: RulesShellState = .empty

    func page(for route: AppRoute) -> AppShellPage {
        switch route {
        case .history:
            AppShellPage(
                accessibilityIdentifier: "appShell.page.history",
                state: .empty(
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
            )
        case .rules:
            rulesPage
        case .browsers:
            AppShellPage(
                accessibilityIdentifier: "appShell.page.browsers",
                state: .empty(
                    iconSystemName: "safari",
                    title: "No browsers are available",
                    message: "Rescan installed applications or add a browser manually.",
                    actions: [
                        PageStateAction(
                            id: AppShellActionID.rescan.rawValue,
                            title: "Rescan",
                            accessibilityIdentifier: "browsers.rescan"
                        ),
                        PageStateAction(
                            id: AppShellActionID.addCustomBrowser.rawValue,
                            title: "Add Custom Browser",
                            accessibilityIdentifier: "browsers.addCustomBrowser"
                        ),
                        PageStateAction(
                            id: AppShellActionID.openApplicationsFolder.rawValue,
                            title: "Open Applications Folder",
                            accessibilityIdentifier: "browsers.openApplicationsFolder"
                        ),
                    ]
                )
            )
        case .settings:
            AppShellPage(
                accessibilityIdentifier: "appShell.page.settings",
                state: .empty(
                    iconSystemName: "gearshape",
                    title: "Settings",
                    message: "Manage link handling, startup, privacy, and updates."
                )
            )
        }
    }

    private var rulesPage: AppShellPage {
        switch rulesState {
        case .empty:
            AppShellPage(
                accessibilityIdentifier: "appShell.page.rules",
                state: .empty(
                    iconSystemName: "list.bullet.rectangle",
                    title: "Unmatched links use your selected fallback",
                    message: "Create a rule to send matching links to a specific browser.",
                    actions: [
                        PageStateAction(
                            id: AppShellActionID.createRule.rawValue,
                            title: "Create Rule",
                            accessibilityIdentifier: "rules.createRule"
                        ),
                    ]
                )
            )
        case .noSearchResults:
            AppShellPage(
                accessibilityIdentifier: "appShell.page.rules",
                state: .empty(
                    iconSystemName: "magnifyingglass",
                    title: "No rules match your search",
                    message: "Clear the search to see all rules.",
                    actions: [
                        PageStateAction(
                            id: AppShellActionID.clearRuleSearch.rawValue,
                            title: "Clear Search",
                            accessibilityIdentifier: "rules.clearSearch"
                        ),
                    ]
                )
            )
        }
    }
}

struct AppShellView: View {
    @Binding private var route: AppRoute

    private let actions: AppShellActions
    private let presentation: AppShellPresentation
    private let recoveryBanner: RecoveryBannerModel?
    private let onRecoveryAction: () -> Void

    init(
        route: Binding<AppRoute>,
        actions: AppShellActions = AppShellActions(),
        rulesState: RulesShellState = .empty,
        recoveryBanner: RecoveryBannerModel? = nil,
        onRecoveryAction: @escaping () -> Void = {}
    ) {
        _route = route
        self.actions = actions
        presentation = AppShellPresentation(rulesState: rulesState)
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
        .frame(minWidth: 760, minHeight: 520)
        .tint(.accentColor)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var detail: some View {
        let page = presentation.page(for: route)

        return VStack(spacing: 0) {
            if let recoveryBanner {
                RecoveryBanner(model: recoveryBanner, onAction: onRecoveryAction)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            PageStateView(model: page.state) { rawAction in
                guard let action = AppShellActionID(rawValue: rawAction) else { return }
                actions.perform(action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle(AppShellDestination.destination(for: route).title)
    }
}
