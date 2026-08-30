import Testing
@testable import PrismNative

@Suite("App shell presentation")
struct AppShellPresentationTests {
    @Test func sidebarKeepsTheOperationalDestinationsInOrder() {
        #expect(AppShellDestination.all.map(\.route) == [
            .overview,
            .history,
            .rules,
            .browsers,
            .settings,
        ])
        #expect(AppShellDestination.all.map(\.accessibilityIdentifier) == [
            "appShell.sidebar.overview",
            "appShell.sidebar.history",
            "appShell.sidebar.rules",
            "appShell.sidebar.browsers",
            "appShell.sidebar.settings",
        ])
        #expect(WorkspaceLayout.previewMinHeight == 220)
        #expect(WorkspaceLayout.cardRadius >= 16)
    }

    @Test func historyEmptyStateExplainsWhenLinksAppearAndOffersTestLink() {
        let page = AppShellPresentation.historyFallback

        #expect(page.kind == .empty)
        #expect(page.title == "Handled links will appear here")
        #expect(page.actions == [
            PageStateAction(
                id: AppShellActionID.testLink.rawValue,
                title: "Test Link",
                accessibilityIdentifier: "history.testLink"
            ),
        ])
    }

}

@Suite("Page state semantics")
struct PageStateSemanticsTests {
    @Test func loadingEmptyFailedAndRecoveryExposeDistinctSemantics() {
        let states = [
            PageStateModel.loading(title: "Loading history"),
            PageStateModel.empty(
                iconSystemName: "clock",
                title: "No history",
                message: "Handled links will appear here."
            ),
            PageStateModel.failed(
                title: "History could not be loaded",
                message: "Try again.",
                action: PageStateAction(id: "retry", title: "Retry", accessibilityIdentifier: "retry")
            ),
            PageStateModel.recovery(
                title: "History needs attention",
                message: "A completed link is waiting to be saved.",
                action: PageStateAction(id: "recover", title: "Retry", accessibilityIdentifier: "recover")
            ),
        ]

        #expect(states.map(\.kind) == [.loading, .empty, .failed, .recovery])
        #expect(states.map(\.accessibilityIdentifier) == [
            "pageState.loading",
            "pageState.empty",
            "pageState.failed",
            "pageState.recovery",
        ])
        #expect(states[0].actions.isEmpty)
        #expect(states[1].actions.isEmpty)
        #expect(states[2].actions.map(\.id) == ["retry"])
        #expect(states[3].actions.map(\.id) == ["recover"])
    }
}

@Suite("Recovery banner semantics")
struct RecoveryBannerSemanticsTests {
    @Test(arguments: RecoveryBannerKind.allCases)
    func everyRecoveryUsesANonColorIconAndExactlyOnePrimaryAction(kind: RecoveryBannerKind) {
        let model = RecoveryBannerModel(
            kind: kind,
            title: "Needs attention",
            message: "Prism needs your help.",
            actionTitle: "Retry",
            actionAccessibilityIdentifier: "recovery.retry"
        )

        #expect(!model.iconSystemName.isEmpty)
        #expect(model.primaryAction.title == "Retry")
        #expect(model.primaryAction.accessibilityIdentifier == "recovery.retry")
        #expect(model.canPerformAction)
    }

    @Test func inProgressRecoveryCannotBeTriggeredAgain() {
        let model = RecoveryBannerModel(
            kind: .historyReconciliationPending,
            title: "History is waiting to be saved",
            message: "Retry when storage is available.",
            actionTitle: "Retry",
            actionAccessibilityIdentifier: "recovery.history.retry",
            isPerformingAction: true
        )

        #expect(!model.canPerformAction)
        #expect(model.accessibilityIdentifier == "recoveryBanner.historyReconciliationPending")
    }
}

@Suite("App shell action dispatch")
@MainActor
struct AppShellActionDispatchTests {
    @Test func everyVisibleActionDispatchesOnlyItsMatchingClosure() {
        var received: [AppShellActionID] = []
        let actions = AppShellActions(
            testLink: { received.append(.testLink) },
            openApplicationsFolder: { received.append(.openApplicationsFolder) },
            openDefaultAppsSettings: { received.append(.openDefaultAppsSettings) },
            restart: { received.append(.restart) }
        )

        for action in AppShellActionID.allCases {
            actions.perform(action)
        }

        #expect(received == AppShellActionID.allCases)
    }
}
