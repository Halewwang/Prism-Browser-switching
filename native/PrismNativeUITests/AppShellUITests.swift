import XCTest

final class AppShellUITests: PrismUITestCase {
    func testSourceRuleEditorKeepsFooterVisibleAndPickerRestoresKeyboardFocus() throws {
        let application = launchFixture("workspace", appearance: .light)
        requireElement("appShell.sidebar.rules", in: application).click()
        let actions = requireElement("rules.rule.00000000-0000-0000-0000-000000000303.actions", in: application)
        XCTAssertTrue(actions.debugDescription.contains("Actions for rule Messages"))
        actions.click()
        let edit = application.menuItems["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.click()
        requireButton("rules.editor.condition", in: application).click()
        _ = requireElement("workspace.picker.search.Source application", in: application)
        application.typeKey(.escape, modifierFlags: [])
        let save = requireButton("rules.editor.save", in: application)
        let match = requireButton("rules.editor.match", in: application)
        XCTAssertEqual(match.value as? String, "Source application")
        match.click()
        let exactDomain = application.buttons["Exact domain"].firstMatch
        XCTAssertTrue(exactDomain.waitForExistence(timeout: 3))
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !exactDomain.exists })
        application.typeKey(.space, modifierFlags: [])
        guard exactDomain.waitForExistence(timeout: 3) else {
            XCTFail("Closing the picker must restore keyboard focus to its trigger")
            return
        }
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(save.isHittable, "The footer must remain available for the taller source-application form")
        try attachWindowScreenshot("review-source-rule-editor", application: application, appearance: .light)
        application.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !save.exists })
    }

    func testBrowserManagementOpensFromApplicationMenu() throws {
        let application = launchFixture("workspace", appearance: .light)
        requireElement("appShell.sidebar.settings", in: application).click()
        application.menuBars.menuBarItems["Prism"].click()
        application.menuItems["Manage Browsers"].click()
        _ = requireButton("browsers.rescan", in: application)
        _ = requireButton("browsers.add", in: application)
        try attachWindowScreenshot("review-browser-management", application: application, appearance: .light)
        requireButton("browsers.done", in: application).click()
    }

    func testShellExposesRealRulesBrowsersAndSettingsPages() throws {
        let application = launchFixture("history", appearance: .light)

        _ = requireElement("appShell.page.history.heading", in: application)
        _ = requireElement("appShell.sidebar.brand", in: application)
        XCTAssertFalse(application.buttons["appShell.openSettings"].exists)

        requireElement("appShell.sidebar.rules", in: application).click()
        _ = requireElement("appShell.page.rules.heading", in: application)
        _ = requirePageStateTitle("Start with your first rule", kind: "empty", in: application)
        _ = requireButton("rules.emptyCreate", in: application)
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
        XCTAssertTrue(application.buttons["settings.checkForUpdates"].exists)
        XCTAssertFalse(application.buttons["settings.checkForUpdates"].isEnabled)
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
        let documentationActions = requireElement(
            "rules.rule.00000000-0000-0000-0000-000000000301.actions",
            in: application
        )
        documentationActions.click()
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
        documentationActions.click()
        let updatedDocumentationUp = requireElement(
            "rules.rule.00000000-0000-0000-0000-000000000301.moveUp",
            in: application
        )
        let updatedDocumentationDown = requireElement(
            "rules.rule.00000000-0000-0000-0000-000000000301.moveDown",
            in: application
        )
        XCTAssertTrue(updatedDocumentationUp.isEnabled)
        XCTAssertFalse(updatedDocumentationDown.isEnabled)
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(application.windows.count, 1)
    }

    func testRuleEditorValidatesConditionAndCancellationDoesNotCreateRule() {
        let application = launchFixture("workspace", appearance: .light)
        requireElement("appShell.sidebar.rules", in: application).click()
        _ = requireElement("appShell.page.rules.heading", in: application)
        _ = requireElement("rules.rule.00000000-0000-0000-0000-000000000301.actions", in: application)
        let ruleActions = application.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "rules.rule.", ".actions")
        )
        let originalRuleCount = ruleActions.count
        XCTAssertEqual(originalRuleCount, 3)

        requireButton("rules.create", in: application).click()
        let save = requireElement("rules.editor.save", in: application)
        XCTAssertFalse(save.isEnabled, "A rule requires a matching condition before it can be saved")
        let condition = requireElement("rules.editor.condition", in: application)
        condition.click()
        condition.typeText("cancelled-rule.example.com")
        XCTAssertTrue(waitUntil(timeout: 3) { save.isEnabled })

        let cancel = application.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !save.exists })
        XCTAssertEqual(ruleActions.count, originalRuleCount, "Cancelling must preserve the saved rule list")
        XCTAssertFalse(application.staticTexts["cancelled-rule.example.com"].exists)
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

    func testSharedSettingsControlsUpdateTheirRealValues() {
        let application = launchFixture("workspace", appearance: .light)
        requireElement("appShell.sidebar.settings", in: application).click()
        let automaticRules = requireElement("settings.automaticRules", in: application)
        let originalValue = String(describing: automaticRules.value ?? "")
        XCTAssertFalse(originalValue.isEmpty)
        automaticRules.click()
        XCTAssertTrue(waitUntil(timeout: 3) { String(describing: automaticRules.value ?? "") != originalValue })
        automaticRules.click()
        XCTAssertTrue(waitUntil(timeout: 3) { String(describing: automaticRules.value ?? "") == originalValue })

        let unmatched = requireElement("settings.unmatchedBehavior", in: application)
        unmatched.click()
        let preferred = application.buttons["Preferred browser"].firstMatch
        XCTAssertTrue(preferred.waitForExistence(timeout: 3))
        preferred.click()
        _ = requireElement("settings.preferredBrowser", in: application)
        XCTAssertEqual(unmatched.value as? String, "Preferred browser")

        unmatched.click()
        XCTAssertTrue(application.buttons["Last used"].firstMatch.waitForExistence(timeout: 3))
        application.activate()
        application.typeKey(.downArrow, modifierFlags: [])
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { unmatched.value as? String == "Last used" })

        requireElement("appShell.sidebar.history", in: application).click()
        requireElement("appShell.sidebar.settings", in: application).click()
        XCTAssertEqual(requireElement("settings.unmatchedBehavior", in: application).value as? String, "Last used")
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
        requireElement("history.row.00000000-0000-0000-0000-000000000203.more", in: noURL).click()
        let reopen = requireElement(
            "history.row.00000000-0000-0000-0000-000000000203.reopen",
            in: noURL
        )
        XCTAssertFalse(reopen.isEnabled)
        noURL.typeKey(.escape, modifierFlags: [])
        let url = requireElement(
            "history.row.00000000-0000-0000-0000-000000000203.url",
            in: noURL
        )
        XCTAssertTrue(accessibilityText(of: url).hasPrefix("Saved URL: URL not saved. Source: Fixture Source."))
        XCTAssertTrue(accessibilityText(of: url).contains("Result: Cancelled. Time: "))
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
        let clear = requireElement("history.clear", in: application)
        XCTAssertFalse(clear.isEnabled, "Clear must remain disabled while any History row is queue-owned")

        let more = requireElement(
            "history.row.00000000-0000-0000-0000-000000000204.more",
            in: application
        )
        more.click()
        let retry = requireElement("history.row.00000000-0000-0000-0000-000000000204.retry", in: application)
        XCTAssertTrue(retry.isEnabled, "A queue-owned failure must keep its recovery action available")
        let delete = requireElement(
            "history.row.00000000-0000-0000-0000-000000000204.delete",
            in: application
        )
        XCTAssertFalse(delete.isEnabled, "Delete must remain disabled while that History row is queue-owned")
    }

    func testUnsafeLegacyURLNeverAppearsInHistoryOrMoreActionsAndCannotReopen() {
        let application = launchFixture("history-unsafe-url", appearance: .dark)
        _ = requireElement("appShell.page.history.heading", in: application)
        let safeURL = requireElement(
            "history.row.00000000-0000-0000-0000-000000000206.url",
            in: application
        )
        XCTAssertTrue(accessibilityText(of: safeURL).hasPrefix("Saved URL: https://history.example/private?safe=visible. Source: Fixture Source."))
        XCTAssertTrue(accessibilityText(of: safeURL).contains("Result: Cancelled. Time: "))

        let more = requireElement(
            "history.row.00000000-0000-0000-0000-000000000206.more",
            in: application
        )
        more.click()
        let reopen = requireElement("history.row.00000000-0000-0000-0000-000000000206.reopen", in: application)
        XCTAssertFalse(reopen.isEnabled, "Only an originally safe stored URL may be reopened")
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

    func testSearchFiltersRecordCountAndDetailsShowsSafeURL() {
        let application = launchFixture("history", appearance: .light)
        let count = requireElement("history.recordCount", in: application)
        XCTAssertEqual(accessibilityText(of: count), "2 records")
        let search = requireElement("history.search", in: application)
        search.click()
        search.typeText("/cancelled")
        XCTAssertTrue(waitUntil(timeout: 3) { self.accessibilityText(of: count) == "1 records" })
        XCTAssertFalse(application.descendants(matching: .any)["history.row.00000000-0000-0000-0000-000000000201.url"].exists)
        requireElement("history.row.00000000-0000-0000-0000-000000000202.url", in: application).click()
        let detailURL = requireElement("history.row.00000000-0000-0000-0000-000000000202.details.url", in: application)
        XCTAssertEqual(accessibilityText(of: detailURL), "https://history.example/cancelled?safe=visible")
        XCTAssertTrue(requireButton("history.row.00000000-0000-0000-0000-000000000202.reopen", in: application).isEnabled)
        requireButton("history.row.00000000-0000-0000-0000-000000000202.details.close", in: application).click()
        XCTAssertTrue(waitUntil(timeout: 3) { !detailURL.exists })
        XCTAssertEqual(accessibilityText(of: count), "1 records")
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
        requireElement("history.row.00000000-0000-0000-0000-000000000202.more", in: application).click()
        _ = requireElement(
            "history.row.00000000-0000-0000-0000-000000000202.reopen",
            in: application
        )
        application.typeKey(.escape, modifierFlags: [])
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
