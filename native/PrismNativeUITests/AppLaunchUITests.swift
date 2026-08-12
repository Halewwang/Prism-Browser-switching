import XCTest

final class AppLaunchUITests: XCTestCase {
    func testLaunchShowsPrismLabel() {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing"]
        application.launch()
        defer { application.terminate() }

        XCTAssertTrue(application.staticTexts["Prism"].waitForExistence(timeout: 5))
    }
}
