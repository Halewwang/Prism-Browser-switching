import XCTest

final class OnboardingUITests: PrismUITestCase {
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

        _ = requirePageStateTitle("Handled links will appear here", in: application)
        _ = requireButton("history.testLink", in: application)
        _ = requireMainWindow(in: application)
        try attachWindowScreenshot(
            "shell-history",
            application: application,
            appearance: appearance
        )

        requireElement("appShell.sidebar.settings", in: application).click()
        _ = requirePageStateTitle("Settings", in: application)
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
        XCTAssertEqual(welcome.label, "Your links, in the right browser")
        XCTAssertTrue(welcome.isHittable)

        let recoveryTitle = requireElement(
            "recoveryBanner.corruptDataRecovered.title",
            in: application
        )
        XCTAssertEqual(recoveryTitle.label, "Prism recovered damaged data")
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
