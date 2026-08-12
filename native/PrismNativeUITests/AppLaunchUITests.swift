import XCTest

final class AppLaunchUITests: PrismUITestCase {
    func testFreshSafeFixtureShowsWelcomeWithoutRestoringRealApplicationState() {
        let application = launchFixture("onboarding")

        _ = requireElement("onboarding.step.welcome", in: application)
        _ = requireButton("onboarding.welcome.continue", in: application)
        _ = requireMainWindow(in: application)
    }

    func testWelcomePrimaryActionCanBeUsedFromTheKeyboard() {
        let application = launchFixture("onboarding")
        _ = requireButton("onboarding.welcome.continue", in: application)

        application.typeKey(.enter, modifierFlags: [])

        _ = requireElement("onboarding.step.linkHandling", in: application)
        _ = requireElement("onboarding.linkHandling.httpStatus", in: application)
        _ = requireElement("onboarding.linkHandling.httpsStatus", in: application)
    }
}
