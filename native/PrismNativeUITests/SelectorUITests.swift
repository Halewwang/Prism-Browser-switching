import AppKit
import XCTest

final class SelectorUITests: XCTestCase {
    private var selectorCaptureURL: URL?

    override func tearDown() {
        if let selectorCaptureURL {
            try? FileManager.default.removeItem(at: selectorCaptureURL)
        }
        selectorCaptureURL = nil
        super.tearDown()
    }

    func testThreeBrowserPanelMatchesFixedFigmaGeometryAndPreservesContextMenu() throws {
        let application = launchSelector(variant: "three", appearance: "light")
        defer { terminateSelector(application) }

        let panel = selectorPanel(in: application)
        assertAppearance(on: panel, expected: "NSAppearanceNameAqua")
        let viewport = element("selector.browserViewport", in: panel)
        let source = element("selector.source", in: panel)
        let url = element("selector.url", in: panel)
        let cancel = element("selector.cancel", in: panel)
        let cards = (1 ... 3).map { element("selector.browser.selector-fixture-\($0)", in: panel) }

        _ = try attachSelectorCapture(name: "selector-three")

        assertSize(panel.frame.size, equals: CGSize(width: 425, height: 200), accuracy: 1)
        assertSize(viewport.frame.size, equals: CGSize(width: 412, height: 142), accuracy: 1)
        assertSize(source.frame.size, equals: CGSize(width: 75, height: 40), accuracy: 1)
        assertSize(url.frame.size, equals: CGSize(width: 248, height: 40), accuracy: 1)
        assertSize(cancel.frame.size, equals: CGSize(width: 79, height: 40), accuracy: 1)

        for card in cards {
            assertSize(card.frame.size, equals: CGSize(width: 130, height: 130), accuracy: 1)
        }
        XCTAssertEqual(cards[0].frame.minX - viewport.frame.minX, 6, accuracy: 1)
        XCTAssertEqual(cards[1].frame.minX - cards[0].frame.maxX, 5, accuracy: 1)
        XCTAssertEqual(cards[2].frame.minX - cards[1].frame.maxX, 5, accuracy: 1)
        XCTAssertEqual(viewport.frame.maxX - cards[2].frame.maxX, 6, accuracy: 1)
        XCTAssertEqual(source.frame.minX - panel.frame.minX, 7, accuracy: 1)
        XCTAssertEqual(source.frame.minY - panel.frame.minY, 7, accuracy: 1)
        XCTAssertEqual(url.frame.minX - panel.frame.minX, 87, accuracy: 1)
        XCTAssertEqual(cancel.frame.minX - panel.frame.minX, 340, accuracy: 1)
        XCTAssertEqual(viewport.frame.minX - panel.frame.minX, 7, accuracy: 1)
        XCTAssertEqual(viewport.frame.minY - panel.frame.minY, 52, accuracy: 1)
        XCTAssertEqual(url.frame.minX - source.frame.maxX, 5, accuracy: 1)
        XCTAssertEqual(cancel.frame.minX - url.frame.maxX, 5, accuracy: 1)

        cards[0].rightClick()
        XCTAssertTrue(
            application.menuItems["Always open this domain in Harness Browser 1"]
                .waitForExistence(timeout: 2)
        )
    }

    func testFiveBrowserPanelShowsThreeAndAHalfThenArrowNavigationRevealsFifth() throws {
        let application = launchSelector(variant: "five", appearance: "light")
        defer { terminateSelector(application) }

        let panel = selectorPanel(in: application)
        assertAppearance(on: panel, expected: "NSAppearanceNameAqua")
        let viewport = element("selector.browserViewport", in: panel)
        let cards = (1 ... 5).map { element("selector.browser.selector-fixture-\($0)", in: panel) }
        let expectedWidth = (412.0 - 6.0 - 3.0 * 8.0) / 3.5

        _ = try attachSelectorCapture(name: "selector-five")

        assertSize(panel.frame.size, equals: CGSize(width: 425, height: 200), accuracy: 1)
        assertSize(viewport.frame.size, equals: CGSize(width: 412, height: 142), accuracy: 1)
        for card in cards where card.exists {
            XCTAssertEqual(card.frame.width, expectedWidth, accuracy: 1)
        }
        for index in 0 ..< 3 {
            XCTAssertEqual(visibleWidth(of: cards[index], in: viewport), expectedWidth, accuracy: 1.5)
        }
        XCTAssertEqual(visibleWidth(of: cards[3], in: viewport), expectedWidth / 2, accuracy: 1.5)
        XCTAssertEqual(visibleWidth(of: cards[4], in: viewport), 0, accuracy: 1.5)

        for _ in 0 ..< 4 {
            panel.typeKey(.rightArrow, modifierFlags: [])
        }
        XCTAssertTrue(waitUntil(timeout: 2) {
            abs(self.visibleWidth(of: cards[4], in: viewport) - expectedWidth) <= 1.5
        })
        XCTAssertTrue(cards[4].label.contains("Selected"))

    }

    func testNumberKeyLaunchesItsMatchingBrowserWithoutASeparateSelectionStep() {
        let application = launchSelector(variant: "three", appearance: "light")
        defer { terminateSelector(application) }

        let panel = selectorPanel(in: application)
        panel.typeKey("2", modifierFlags: [])

        XCTAssertTrue(waitUntil(timeout: 2) { !panel.exists })
    }

    func testDraggingFromBrowserCardScrollsWithoutActivatingABrowser() {
        let application = launchSelector(variant: "five", appearance: "light")
        defer { terminateSelector(application) }

        let panel = selectorPanel(in: application)
        let viewport = element("selector.browserViewport", in: panel)
        let fifth = element("selector.browser.selector-fixture-5", in: panel)
        let first = element("selector.browser.selector-fixture-1", in: panel)
        let second = element("selector.browser.selector-fixture-2", in: panel)
        let start = second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))

        XCTAssertEqual(visibleWidth(of: fifth, in: viewport), 0, accuracy: 1.5)
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(waitUntil(timeout: 2) {
            self.visibleWidth(of: fifth, in: viewport) > 0
        })
        XCTAssertTrue(first.label.contains("Selected"))
        XCTAssertFalse(second.label.contains("Selected"))
        XCTAssertTrue(panel.exists)
    }

    func testSwipeLeftAutomationEquivalentRevealsLaterBrowsers() {
        let application = launchSelector(variant: "five", appearance: "light")
        defer { terminateSelector(application) }

        let panel = selectorPanel(in: application)
        let viewport = element("selector.browserViewport", in: panel)
        let fifth = element("selector.browser.selector-fixture-5", in: panel)

        XCTAssertEqual(visibleWidth(of: fifth, in: viewport), 0, accuracy: 1.5)
        viewport.swipeLeft()
        XCTAssertTrue(waitUntil(timeout: 2) {
            self.visibleWidth(of: fifth, in: viewport) > 0
        })
    }

    func testEscapeCancelsTheExactHarnessRequestAndHidesThePanel() {
        let application = launchSelector(variant: "three", appearance: "light")
        defer { terminateSelector(application) }

        let panel = selectorPanel(in: application)
        panel.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(waitUntil(timeout: 2) { !panel.exists })
    }

    func testCancelControlCancelsTheExactHarnessRequestAndHidesThePanel() {
        let application = launchSelector(variant: "three", appearance: "light")
        defer { terminateSelector(application) }

        let panel = selectorPanel(in: application)
        element("selector.cancel", in: panel).click()

        XCTAssertTrue(waitUntil(timeout: 2) { !panel.exists })
    }

    func testDarkAppearanceUsesDarkSurfacesAndKeepsTextVisible() throws {
        let application = launchSelector(variant: "three", appearance: "dark")
        defer { terminateSelector(application) }

        let panel = selectorPanel(in: application)
        assertDarkAppearance(on: panel)
        let image = try attachSelectorCapture(name: "selector-three-dark")
        XCTAssertLessThan(try luminance(of: image, x: 210, y: 110), 0.20)
        XCTAssertLessThan(try luminance(of: image, x: 200, y: 20), 0.20)
        XCTAssertGreaterThan(
            try brightestLuminance(in: image),
            0.65,
            "The selector capture contains no visible light content and may be obscured by macOS screen privacy."
        )
        XCTAssertGreaterThan(
            try brightPixelRatio(in: image, above: 0.45),
            0.002,
            "The selector capture contains too little visible UI structure and may be obscured by macOS screen privacy."
        )
        XCTAssertTrue(element("selector.cancel", in: panel).exists)
        let firstBrowser = element("selector.browser.selector-fixture-1", in: panel)
        XCTAssertTrue(firstBrowser.label.contains("Selected"))

        firstBrowser.rightClick()
        let domainMenuItem = application.menuItems["Always open this domain in Harness Browser 1"]
        XCTAssertTrue(domainMenuItem.waitForExistence(timeout: 2))
    }

    func testDarkFailureEmptyAndRecoveryStatesRemainAccessible() throws {
        for variant in ["failed", "empty", "recovery"] {
            let application = launchSelector(variant: variant, appearance: "dark")
            let panel = selectorPanel(in: application)
            assertDarkAppearance(on: panel)

            switch variant {
            case "failed":
                let failureValue = element("selector.url", in: panel).value as? String ?? ""
                XCTAssertTrue(
                    failureValue.contains("Harness launch failed"),
                    "Unexpected failure value: \(failureValue)"
                )
            case "empty":
                XCTAssertTrue(element("selector.rescan", in: panel).exists)
                XCTAssertTrue(element("selector.openBrowserManagement", in: panel).exists)
            case "recovery":
                XCTAssertTrue(element("selector.recovery", in: panel).exists)
            default:
                XCTFail("Unexpected selector fixture")
            }

            let capture = try attachSelectorCapture(name: "selector-\(variant)-dark")
            XCTAssertGreaterThan(
                try brightestLuminance(in: capture),
                0.65,
                "The \(variant) selector capture contains no visible light content and may be obscured by macOS screen privacy."
            )
            XCTAssertGreaterThan(
                try brightPixelRatio(in: capture, above: 0.45),
                0.002,
                "The \(variant) selector capture contains too little visible UI structure and may be obscured by macOS screen privacy."
            )
            terminateSelector(application)
        }
    }

    private func launchSelector(variant: String, appearance: String) -> XCUIApplication {
        if let selectorCaptureURL {
            try? FileManager.default.removeItem(at: selectorCaptureURL)
        }
        let captureURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("prism-selector-\(UUID().uuidString).png")
        try? FileManager.default.removeItem(at: captureURL)
        selectorCaptureURL = captureURL
        let application = XCUIApplication()
        application.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "--ui-testing", "--selector-harness", variant,
            "--selector-appearance", appearance,
            "--selector-capture-path", captureURL.path,
        ]
        application.launch()
        XCTAssertEqual(application.state, .runningForeground)
        return application
    }

    private func selectorPanel(in application: XCUIApplication) -> XCUIElement {
        let panel = application.descendants(matching: .any)
            .matching(identifier: "selector.panel")
            .firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        return panel
    }

    private func element(_ identifier: String, in root: XCUIElement) -> XCUIElement {
        let element = root.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing element \(identifier)")
        return element
    }

    private func visibleWidth(of element: XCUIElement, in viewport: XCUIElement) -> CGFloat {
        guard element.exists else { return 0 }
        return element.frame.intersection(viewport.frame).width
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < deadline
        return condition()
    }

    private func terminateSelector(_ application: XCUIApplication) {
        guard application.state != .notRunning else { return }
        application.terminate()
        XCTAssertTrue(
            waitUntil(timeout: 5) { application.state == .notRunning },
            "Selector harness must exit before another Prism UI fixture starts."
        )
    }

    private func assertSize(
        _ actual: CGSize,
        equals expected: CGSize,
        accuracy: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    private func attachSelectorCapture(name: String) throws -> NSImage {
        let url = try XCTUnwrap(selectorCaptureURL)
        XCTAssertTrue(waitUntil(timeout: 3) {
            FileManager.default.fileExists(atPath: url.path)
        }, "Missing selector content capture at \(url.path)")
        let image = try XCTUnwrap(NSImage(contentsOf: url))
        assertSize(image.size, equals: CGSize(width: 425, height: 200), accuracy: 1)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    private func assertDarkAppearance(on panel: XCUIElement) {
        assertAppearance(on: panel, expected: "NSAppearanceNameDarkAqua")
    }

    private func assertAppearance(on panel: XCUIElement, expected: String) {
        let value = panel.value as? String ?? ""
        XCTAssertTrue(value.contains("panel=\(expected)"), "Unexpected panel appearance: \(value)")
        XCTAssertTrue(value.contains("hosting=\(expected)"), "Unexpected hosting appearance: \(value)")
    }

    private func luminance(of image: NSImage, x: Int, y: Int) throws -> Double {
        let bitmap = try bitmap(of: image)
        let scaleX = CGFloat(bitmap.pixelsWide) / image.size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / image.size.height
        let color = try XCTUnwrap(bitmap.colorAt(
            x: Int(CGFloat(x) * scaleX),
            y: bitmap.pixelsHigh - 1 - Int(CGFloat(y) * scaleY)
        )?.usingColorSpace(.sRGB))
        let convert: (CGFloat) -> Double = { component in
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * convert(color.redComponent)
            + 0.7152 * convert(color.greenComponent)
            + 0.0722 * convert(color.blueComponent)
    }

    private func brightestLuminance(in image: NSImage) throws -> Double {
        let bitmap = try bitmap(of: image)
        let stride = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 100)
        var brightest = 0.0
        for y in Swift.stride(from: 0, to: bitmap.pixelsHigh, by: stride) {
            for x in Swift.stride(from: 0, to: bitmap.pixelsWide, by: stride) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                brightest = max(brightest, relativeLuminance(color))
            }
        }
        return brightest
    }

    private func brightPixelRatio(in image: NSImage, above threshold: Double) throws -> Double {
        let bitmap = try bitmap(of: image)
        let stride = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 100)
        var brightPixels = 0
        var sampledPixels = 0
        for y in Swift.stride(from: 0, to: bitmap.pixelsHigh, by: stride) {
            for x in Swift.stride(from: 0, to: bitmap.pixelsWide, by: stride) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                sampledPixels += 1
                if relativeLuminance(color) > threshold { brightPixels += 1 }
            }
        }
        return sampledPixels == 0 ? 0 : Double(brightPixels) / Double(sampledPixels)
    }

    private func bitmap(of image: NSImage) throws -> NSBitmapImageRep {
        let data = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: data))
    }

    private func relativeLuminance(_ color: NSColor) -> Double {
        let convert: (CGFloat) -> Double = { component in
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * convert(color.redComponent)
            + 0.7152 * convert(color.greenComponent)
            + 0.0722 * convert(color.blueComponent)
    }
}
