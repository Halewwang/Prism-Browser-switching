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
