import XCTest

final class AppShellUITests: PrismUITestCase {
    func testShellExposesAllFourDestinationsAndTheirRequiredEmptyActions() {
        let application = launchFixture("shell", appearance: .light)

        _ = requirePageStateTitle("Handled links will appear here", in: application)
        _ = requireButton("history.testLink", in: application)

        requireElement("appShell.sidebar.rules", in: application).click()
        _ = requirePageStateTitle("Unmatched links use your selected fallback", in: application)
        _ = requireButton("rules.createRule", in: application)

        requireElement("appShell.sidebar.browsers", in: application).click()
        _ = requirePageStateTitle("No browsers are available", in: application)
        _ = requireButton("browsers.rescan", in: application)
        _ = requireButton("browsers.addCustomBrowser", in: application)
        _ = requireButton("browsers.openApplicationsFolder", in: application)

        requireElement("appShell.sidebar.settings", in: application).click()
        _ = requirePageStateTitle("Settings", in: application)
        _ = requireButton("appShell.openSettings", in: application)
        XCTAssertEqual(application.windows.count, 1)
    }

    func testDockStyleReopenPreservesRouteAndNeverDuplicatesTheMainWindow() {
        let application = launchFixture("shell", appearance: .light)
        requireElement("appShell.sidebar.settings", in: application).click()
        _ = requirePageStateTitle("Settings", in: application)

        application.activate()
        application.activate()
        _ = requirePageStateTitle("Settings", in: application)
        XCTAssertEqual(application.windows.count, 1)

        let window = requireMainWindow(in: application)
        let close = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.click()
        XCTAssertTrue(waitUntil(timeout: 5) { application.windows.count == 0 })

        application.activate()
        _ = requireMainWindow(in: application)
        _ = requirePageStateTitle("Settings", in: application)
        XCTAssertEqual(application.windows.count, 1)

        requireElement("appShell.sidebar.history", in: application).click()
        _ = requirePageStateTitle("Handled links will appear here", in: application)
        application.activate()
        application.activate()
        _ = requirePageStateTitle("Handled links will appear here", in: application)
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
        XCTAssertTrue(
            noURL.staticTexts["URL not saved"].firstMatch.waitForExistence(timeout: 5),
            "History must state that a URL was not retained instead of exposing a raw value"
        )
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
        for secret in [
            "username", "password", "token", "secret", "api_key",
            "client_secret", "refresh_token", "redacted", "fragment",
        ] {
            XCTAssertFalse(
                accessibilityHierarchy.localizedCaseInsensitiveContains(secret),
                "History accessibility must not expose the legacy \(secret) component"
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
