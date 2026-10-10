import XCTest

final class OnboardingUITests: PrismUITestCase {
    func testChineseOnboardingFollowsPenWindowLayout() throws {
        let application = launchFixture("partial-handler", appearance: .light, language: "zh-Hans")
        let welcome = requireElement("onboarding.step.welcome", in: application)
        XCTAssertTrue(accessibilityText(of: welcome).contains("你的链接"))
        let window = requireMainWindow(in: application)
        XCTAssertEqual(window.frame.width, 668, accuracy: 1)
        XCTAssertEqual(window.frame.height, 578, accuracy: 1)
        XCTAssertGreaterThanOrEqual(requireElement("onboarding.progress.label", in: application).frame.minY - window.frame.minY, 48)
        try attachWindowScreenshot("pen-onboarding-welcome-zh", application: application, appearance: .light)

        requireButton("onboarding.welcome.continue", in: application).click()
        _ = requireElement("onboarding.step.linkHandling", in: application)
        try attachWindowScreenshot("pen-onboarding-link-handling-zh", application: application, appearance: .light)
        requireButton("onboarding.linkHandling.finishLater", in: application).click()
        requireButton("onboarding.browsers.rescan", in: application).click()
        _ = requireElement("onboarding.step.testLink", in: application)
        _ = requireElement("onboarding.browsers.browser.invalid.prism.fixture.browser", in: application)
        XCTAssertTrue(requireButton("onboarding.browsers.rescan", in: application).isHittable)
        XCTAssertTrue(requireButton("onboarding.browsers.addCustomBrowser", in: application).isHittable)
        XCTAssertTrue(requireButton("onboarding.testLink.start", in: application).isHittable)
        try attachWindowScreenshot("pen-onboarding-browsers-zh", application: application, appearance: .light)

        terminateFixture(application)
        let workspace = launchFixture("workspace", appearance: .light, language: "zh-Hans")
        _ = requireElement("appShell.page.history.heading", in: workspace)
        try attachWindowScreenshot("pen-history-zh", application: workspace, appearance: .light)
        requireElement("appShell.sidebar.rules", in: workspace).click()
        _ = requireElement("appShell.page.rules.heading", in: workspace)
        XCTAssertTrue(workspace.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "域名及子域名", "域名及子域名")).firstMatch.waitForExistence(timeout: 3))
        try attachWindowScreenshot("pen-rules-zh", application: workspace, appearance: .light)
        requireButton("rules.create", in: workspace).click()
        let save = requireElement("rules.editor.save", in: workspace)
        XCTAssertFalse(save.isEnabled)
        try attachWindowScreenshot("pen-rule-editor-zh", application: workspace, appearance: .light)
        workspace.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !save.exists })
        requireElement("appShell.sidebar.settings", in: workspace).click()
        _ = requireElement("appShell.page.settings.heading", in: workspace)
        try attachWindowScreenshot("pen-settings-zh", application: workspace, appearance: .light)
    }

    func testLightOnboardingUsesSeparateHandlersRealSelectorAndOpensHistory() throws {
        try runSuccessfulOnboardingAndRecovery(appearance: .light)
    }

    func testDarkOnboardingUsesSeparateHandlersRealSelectorAndOpensHistory() throws {
        try runSuccessfulOnboardingAndRecovery(appearance: .dark)
    }

    func testRejectedBrowserHandoffDoesNotCompleteOnboarding() throws {
        let application = launchFixture("launch-failure", appearance: .light)
        advanceToTestLink(in: application)

        requireButton("onboarding.testLink.start", in: application).click()
        let panel = requireElement("selector.panel", in: application)
        requireElement("selector.browser.invalid.prism.fixture.browser", in: application).click()

        let failureValue = requireElement("selector.url", in: application).value as? String ?? ""
        XCTAssertTrue(failureValue.contains("launch_failed"), "Unexpected selector failure: \(failureValue)")
        panel.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })

        _ = requireElement("onboarding.step.testLink", in: application)
        _ = requireElement("onboarding.alert", in: application)
        _ = requireButton("onboarding.testLink.retry", in: application)
        XCTAssertFalse(application.buttons["history.testLink"].exists)
        try attachWindowScreenshot(
            "onboarding-launch-failure",
            application: application,
            appearance: .light
        )
    }

    func testNoBrowserStateStaysRecoverableWithoutOpeningSystemApplications() throws {
        let application = launchFixture("empty-browsers", appearance: .light)
        requireButton("onboarding.welcome.continue", in: application).click()
        _ = requireElement("onboarding.step.browsers", in: application)

        requireButton("onboarding.browsers.rescan", in: application).click()
        _ = requireElement("onboarding.alert", in: application)
        let rescan = requireButton("onboarding.browsers.rescan", in: application)
        let addCustom = requireButton("onboarding.browsers.addCustomBrowser", in: application)
        let openApplications = requireButton("onboarding.browsers.openApplicationsFolder", in: application)

        addCustom.click()
        openApplications.click()
        _ = requireElement("onboarding.step.browsers", in: application)
        XCTAssertTrue(rescan.isHittable)
        XCTAssertEqual(application.windows.count, 1)
        try attachWindowScreenshot(
            "onboarding-empty-browser-recovery",
            application: application,
            appearance: .light
        )
    }

    func testLightOnboardingRecoveryBannerKeepsWelcomeAndFooterActionsVisible() throws {
        try runOnboardingRecoveryBanner(appearance: .light)
    }

    func testDarkOnboardingRecoveryBannerKeepsWelcomeAndFooterActionsVisible() throws {
        try runOnboardingRecoveryBanner(appearance: .dark)
    }

    private func runSuccessfulOnboardingAndRecovery(
        appearance: PrismUITestAppearance
    ) throws {
        let application = launchFixture("partial-handler", appearance: appearance)
        _ = requireElement("onboarding.step.welcome", in: application)
        let welcomeWindow = requireMainWindow(in: application)
        XCTAssertEqual(welcomeWindow.frame.width, 668, accuracy: 1)
        XCTAssertEqual(welcomeWindow.frame.height, 578, accuracy: 1)
        try attachWindowScreenshot(
            "onboarding-welcome",
            application: application,
            appearance: appearance,
            verifiesAppearance: true
        )

        requireButton("onboarding.welcome.continue", in: application).click()
        _ = requireElement("onboarding.step.linkHandling", in: application)
        let http = requireElement("onboarding.linkHandling.httpStatus", in: application)
        let https = requireElement("onboarding.linkHandling.httpsStatus", in: application)
        XCTAssertTrue(http.label.contains("HTTP links: Prism is active"), "Unexpected HTTP status: \(http.label)")
        XCTAssertTrue(https.label.contains("HTTPS links: Needs attention"), "Unexpected HTTPS status: \(https.label)")
        try attachWindowScreenshot(
            "onboarding-link-handling",
            application: application,
            appearance: appearance
        )

        requireButton("onboarding.linkHandling.finishLater", in: application).click()
        _ = requireElement("onboarding.step.browsers", in: application)
        _ = requireElement("onboarding.browsers.empty", in: application)
        try attachWindowScreenshot(
            "onboarding-browsers",
            application: application,
            appearance: appearance
        )

        requireButton("onboarding.browsers.rescan", in: application).click()
        _ = requireElement("onboarding.step.testLink", in: application)
        _ = requireElement("onboarding.testLink.explanation", in: application)
        try attachWindowScreenshot(
            "onboarding-test-link",
            application: application,
            appearance: appearance
        )

        requireButton("onboarding.testLink.start", in: application).click()
        let selector = requireElement("selector.panel", in: application)
        requireElement("selector.browser.invalid.prism.fixture.browser", in: application).click()
        XCTAssertTrue(waitUntil(timeout: 5) { !selector.exists })

        let finish = requireButton("onboarding.testLink.finish", in: application)
        XCTAssertTrue(finish.isHittable)
        XCTAssertTrue(requireButton("onboarding.testLink.retest", in: application).isHittable)
        XCTAssertFalse(application.descendants(matching: .any)["appShell.page.history.heading"].exists)
        try attachWindowScreenshot("onboarding-complete", application: application, appearance: appearance)
        requireButton("onboarding.testLink.retest", in: application).click()
        let repeatedSelector = requireElement("selector.panel", in: application)
        requireElement("selector.browser.invalid.prism.fixture.browser", in: application).click()
        XCTAssertTrue(waitUntil(timeout: 5) { !repeatedSelector.exists })
        requireButton("onboarding.testLink.finish", in: application).click()

        let historyURL = application.descendants(matching: .any).matching(
            NSPredicate(format: "identifier ENDSWITH %@", ".url")
        ).firstMatch
        XCTAssertTrue(historyURL.waitForExistence(timeout: 5))
        XCTAssertTrue(
            accessibilityText(of: historyURL).contains("example.com/prism-onboarding-test"),
            "A successful test handoff must create the corresponding History row"
        )
        _ = requireMainWindow(in: application)
        try attachWindowScreenshot(
            "shell-history",
            application: application,
            appearance: appearance
        )

        requireElement("appShell.sidebar.settings", in: application).click()
        _ = requireElement("appShell.page.settings.heading", in: application)
        try attachWindowScreenshot(
            "shell-settings",
            application: application,
            appearance: appearance
        )
        terminateFixture(application)

        let recoveryApplication = launchFixture("recovery", appearance: appearance)
        _ = requirePageStateTitle(
            "Prism could not restore pending links",
            kind: "recovery",
            in: recoveryApplication
        )
        let retry = requireButton("recovery.restoration.retry", in: recoveryApplication)
        XCTAssertEqual(
            recoveryApplication.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "recovery.")
            ).count,
            1,
            "Startup recovery must expose one safe recovery action"
        )
        try attachWindowScreenshot(
            "startup-recovery",
            application: recoveryApplication,
            appearance: appearance
        )
        retry.click()
        _ = requirePageStateTitle(
            "Prism could not restore pending links",
            kind: "recovery",
            in: recoveryApplication
        )
        _ = requireButton("recovery.restoration.retry", in: recoveryApplication)
        XCTAssertEqual(recoveryApplication.windows.count, 1)
    }

    private func advanceToTestLink(in application: XCUIApplication) {
        requireButton("onboarding.welcome.continue", in: application).click()
        _ = requireElement("onboarding.step.linkHandling", in: application)
        requireButton("onboarding.linkHandling.finishLater", in: application).click()
        _ = requireElement("onboarding.step.browsers", in: application)
        requireButton("onboarding.browsers.rescan", in: application).click()
        _ = requireElement("onboarding.step.testLink", in: application)
    }

    private func runOnboardingRecoveryBanner(
        appearance: PrismUITestAppearance
    ) throws {
        let application = launchFixture("onboarding-recovery", appearance: appearance)
        let window = requireMainWindow(in: application)
        let welcome = requireElement("onboarding.step.welcome", in: application)
        XCTAssertEqual(welcome.label, "Your links,\nyour way to browse.")
        XCTAssertTrue(welcome.isHittable)

        let recoveryTitle = requireElement(
            "recoveryBanner.corruptDataRecovered.title",
            in: application
        )
        XCTAssertEqual(accessibilityText(of: recoveryTitle), "Prism recovered damaged data")
        XCTAssertTrue(recoveryTitle.isHittable)

        let restart = requireButton("recovery.restart", in: application)
        let continueButton = requireButton("onboarding.welcome.continue", in: application)
        XCTAssertTrue(window.frame.contains(restart.frame))
        XCTAssertTrue(window.frame.contains(continueButton.frame))
        XCTAssertEqual(application.windows.count, 1)

        try attachWindowScreenshot(
            "onboarding-recovery-banner",
            application: application,
            appearance: appearance,
            verifiesAppearance: true
        )

        restart.click()
        _ = requireElement("onboarding.step.welcome", in: application)
        continueButton.click()
        _ = requireElement("onboarding.step.linkHandling", in: application)
        XCTAssertEqual(application.windows.count, 1)
    }
}
