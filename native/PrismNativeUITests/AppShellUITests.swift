import XCTest

final class AppShellUITests: PrismUITestCase {
    func testShellExposesRealRulesBrowsersAndSettingsPages() throws {
        let application = launchFixture("history", appearance: .light)

        _ = requireElement("appShell.page.history.heading", in: application)
        _ = requireElement("appShell.sidebar.brand", in: application)
        XCTAssertFalse(application.buttons["appShell.openSettings"].exists)

        requireElement("appShell.sidebar.rules", in: application).click()
        _ = requireElement("appShell.page.rules.heading", in: application)
        XCTAssertTrue(application.staticTexts["No routing rules"].firstMatch.waitForExistence(timeout: 5))
        _ = requireButton("rules.create", in: application)
        try attachWindowScreenshot(
            "rules-management",
            application: application,
            appearance: .light
        )

        requireElement("appShell.sidebar.settings", in: application).click()
        _ = requireElement("appShell.page.settings.heading", in: application)
        _ = requireElement("settings.showMenuBarItem", in: application)
        _ = requireElement("settings.automaticRules", in: application)
        _ = requireElement("settings.historyEnabled", in: application)
        _ = requireElement("settings.setDefaultHandler", in: application)
        _ = requireElement("settings.launchAtLogin", in: application)
        let automaticUpdateChecks = requireElement("settings.automaticUpdateChecks", in: application)
        XCTAssertFalse(automaticUpdateChecks.isEnabled)
        XCTAssertFalse(application.buttons["settings.checkForUpdates"].exists)
        try attachWindowScreenshot(
            "settings-management",
            application: application,
            appearance: .light
        )
        XCTAssertEqual(application.windows.count, 1)
    }

    func testWorkspaceRulesKeepPriorityActionable() throws {
        let application = launchFixture("workspace", appearance: .dark)

        requireElement("appShell.sidebar.rules", in: application).click()
        _ = requireElement("appShell.page.rules.heading", in: application)
        let documentationUp = requireElement(
            "rules.rule.00000000-0000-0000-0000-000000000301.moveUp",
            in: application
        )
        let documentationDown = requireElement(
            "rules.rule.00000000-0000-0000-0000-000000000301.moveDown",
            in: application
        )
        XCTAssertFalse(documentationUp.isEnabled)
        XCTAssertTrue(documentationDown.isEnabled)

        documentationDown.click()
        XCTAssertTrue(waitUntil(timeout: 3) { documentationUp.isEnabled })
        XCTAssertEqual(application.windows.count, 1)
    }

    func testRepeatedActivationPreservesRouteAndNeverDuplicatesTheMainWindow() {
        let application = launchFixture("history", appearance: .light)
        requireElement("appShell.sidebar.settings", in: application).click()
        _ = requireElement("appShell.page.settings.heading", in: application)

        application.activate()
        application.activate()
        _ = requireElement("appShell.page.settings.heading", in: application)
        XCTAssertEqual(application.windows.count, 1)

        requireElement("appShell.sidebar.history", in: application).click()
        _ = requireElement("appShell.page.history.heading", in: application)
        application.activate()
        application.activate()
        _ = requireElement("appShell.page.history.heading", in: application)
        XCTAssertEqual(application.windows.count, 1)
    }
}

final class HistoryUITests: PrismUITestCase {
    func testHistoryContentUsesUniqueRowActionsInLightAndDarkAppearance() throws {
        let light = try verifyHistoryContent(appearance: .light)
        terminateFixture(light)
        _ = try verifyHistoryContent(appearance: .dark)
    }

    func testHistoryLoadFailureAndNoURLRowsRemainExplicitlyRecoverable() throws {
        let failed = launchFixture("history-load-failure", appearance: .light)
        _ = requirePageStateTitle(
            "History could not be loaded",
            kind: "failed",
            in: failed
        )
        _ = requireButton("history.retryLoad", in: failed)
        terminateFixture(failed)

        let noURL = launchFixture("history-no-url", appearance: .dark)
        _ = requireElement("appShell.page.history.heading", in: noURL)
        let reopen = requireElement(
            "history.row.00000000-0000-0000-0000-000000000203.reopen",
            in: noURL
        )
        XCTAssertFalse(reopen.isEnabled)
        let url = requireElement(
            "history.row.00000000-0000-0000-0000-000000000203.url",
            in: noURL
        )
        XCTAssertEqual(accessibilityText(of: url), "Saved URL: URL not saved")
        try attachWindowScreenshot(
            "history-no-url",
            application: noURL,
            appearance: .dark,
            verifiesAppearance: true
        )
    }

    func testQueueOwnedFailedHistoryRowDisablesClearAndKeepsTheRecoveryActionVisible() {
        let application = launchFixture("history-actions", appearance: .light)
        _ = requireElement("appShell.page.history.heading", in: application)
        _ = requireElement(
            "history.row.00000000-0000-0000-0000-000000000204.retry",
            in: application
        )
        let clear = requireElement("history.clear", in: application)
        XCTAssertFalse(clear.isEnabled, "Clear must remain disabled while any History row is queue-owned")

        let more = requireElement(
            "history.row.00000000-0000-0000-0000-000000000204.more",
            in: application
        )
        more.click()
        let delete = requireElement(
            "history.row.00000000-0000-0000-0000-000000000204.delete",
            in: application
        )
        XCTAssertFalse(delete.isEnabled, "Delete must remain disabled while that History row is queue-owned")
    }

    func testUnsafeLegacyURLNeverAppearsInHistoryOrMoreActionsAndCannotReopen() {
        let application = launchFixture("history-unsafe-url", appearance: .dark)
        _ = requireElement("appShell.page.history.heading", in: application)
        let reopen = requireElement(
            "history.row.00000000-0000-0000-0000-000000000206.reopen",
            in: application
        )
        XCTAssertFalse(reopen.isEnabled, "Only an originally safe stored URL may be reopened")
        let safeURL = requireElement(
            "history.row.00000000-0000-0000-0000-000000000206.url",
            in: application
        )
        XCTAssertEqual(
            accessibilityText(of: safeURL),
            "Saved URL: https://history.example/private?safe=visible"
        )

        let more = requireElement(
            "history.row.00000000-0000-0000-0000-000000000206.more",
            in: application
        )
        more.click()
        _ = requireElement(
            "history.row.00000000-0000-0000-0000-000000000206.delete",
            in: application
        )

        let accessibilityHierarchy = application.debugDescription
        for unsafeURLPart in [
            "username:password@",
            "token=secret",
            "password=redacted",
            "api_key=redacted",
            "client_secret=redacted",
            "refresh_token=redacted",
            "#fragment",
        ] {
            XCTAssertFalse(
                accessibilityHierarchy.localizedCaseInsensitiveContains(unsafeURLPart),
                "History accessibility must not expose \(unsafeURLPart) from the legacy URL"
            )
        }
    }

    private func verifyHistoryContent(appearance: PrismUITestAppearance) throws -> XCUIApplication {
        let application = launchFixture("history", appearance: appearance)
        _ = requireElement("appShell.page.history.heading", in: application)
        _ = requireElement(
            "history.row.00000000-0000-0000-0000-000000000201.more",
            in: application
        )
        _ = requireElement(
            "history.row.00000000-0000-0000-0000-000000000202.more",
            in: application
        )
        _ = requireButton(
            "history.row.00000000-0000-0000-0000-000000000202.reopen",
            in: application
        )
        _ = requireButton("history.clear", in: application)
        try attachWindowScreenshot(
            "history-content",
            application: application,
            appearance: appearance,
            verifiesAppearance: true
        )
        return application
    }
}
