import XCTest

@MainActor final class UpdateUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--update-harness"]
        app.launch()
    }
    override func tearDown() { app.terminate() }
    func testDownloadVerifiesBeforeOfferingInstallAndPendingLinksKeepAppOpen() {
        let download = app.buttons["update.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["update.install"].exists)
        download.click()
        XCTAssertTrue(app.buttons["update.cancel"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["update.ready"].waitForExistence(timeout: 8))
        let install = app.buttons["update.install"]
        XCTAssertTrue(install.isEnabled)
        install.click()
        XCTAssertTrue(app.staticTexts["update.message"].waitForExistence(timeout: 3))
        XCTAssertTrue(install.isEnabled)
        XCTAssertEqual(app.state, .runningForeground)
    }
    func testCancellationAllowsFreshDownload() {
        app.buttons["update.download"].click()
        let cancel = app.buttons["update.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.click()
        XCTAssertTrue(app.buttons["update.download"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["update.install"].exists)
    }
}
