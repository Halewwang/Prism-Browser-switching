import AppKit
import XCTest

enum PrismUITestAppearance: String {
    case light = "Light"
    case dark = "Dark"

    var attachmentSlug: String { rawValue.lowercased() }
}

class PrismUITestCase: XCTestCase {
    private var launchedApplications: [XCUIApplication] = []

    override func tearDown() {
        for application in launchedApplications.reversed() where application.state != .notRunning {
            terminateFixture(application)
        }
        launchedApplications.removeAll()
        super.tearDown()
    }

    func launchFixture(
        _ fixture: String,
        appearance: PrismUITestAppearance = .light,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", appearance.rawValue,
            "--ui-testing", "--app-fixture", fixture,
        ]
        launchedApplications.append(application)
        application.launch()

        // Wait until the fixture owns its normal AppKit window before asking
        // XCTest to bring it forward. Activating during the app-launch phase
        // can itself race the window server and leave a macOS UI test waiting
        // for a background-only process.
        _ = requireMainWindow(in: application, file: file, line: line)
        application.activate()
        application.activate()
        _ = waitUntil(timeout: 2, file: file, line: line) {
            application.state == .runningForeground
        }
        return application
    }

    func terminateFixture(
        _ application: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard application.state != .notRunning else { return }
        application.terminate()
        _ = waitUntil(timeout: timeout, file: file, line: line) {
            application.state == .notRunning
        }
    }

    @discardableResult
    func requireMainWindow(
        in application: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let window = application.windows.firstMatch
        guard window.waitForExistence(timeout: 8) else {
            attachAXHierarchy(of: application, name: "missing-main-window")
            XCTFail("The safe fixture did not expose a main window", file: file, line: line)
            return window
        }

        XCTAssertEqual(
            application.windows.count,
            1,
            "Application fixtures must expose exactly one main window",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(window.frame.width, 760, file: file, line: line)
        XCTAssertGreaterThanOrEqual(window.frame.height, 520, file: file, line: line)
        return window
    }

    func requireElement(
        _ identifier: String,
        in application: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let query = application.descendants(matching: .any).matching(identifier: identifier)
        let element = query.firstMatch
        guard element.waitForExistence(timeout: timeout) else {
            attachAXHierarchy(of: application, name: "missing-\(safeAttachmentName(identifier))")
            XCTFail("Missing AX element \(identifier)", file: file, line: line)
            return element
        }
        XCTAssertEqual(
            query.count,
            1,
            "AX identifier \(identifier) must resolve to one element, not a propagated container subtree",
            file: file,
            line: line
        )
        return element
    }

    func requireButton(
        _ identifier: String,
        in application: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let query = application.buttons.matching(identifier: identifier)
        let button = query.firstMatch
        guard button.waitForExistence(timeout: timeout) else {
            attachAXHierarchy(of: application, name: "missing-button-\(safeAttachmentName(identifier))")
            XCTFail("Missing AX button \(identifier)", file: file, line: line)
            return button
        }
        XCTAssertEqual(query.count, 1, "Button identifier \(identifier) is not unique", file: file, line: line)
        XCTAssertTrue(button.isEnabled, "Button \(identifier) is disabled", file: file, line: line)
        XCTAssertTrue(button.isHittable, "Button \(identifier) is not visible or hittable", file: file, line: line)
        return button
    }

    @discardableResult
    func requirePageStateTitle(
        _ expectedTitle: String,
        kind: String = "empty",
        in application: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let title = requireElement(
            "pageState.\(kind).title",
            in: application,
            file: file,
            line: line
        )
        XCTAssertEqual(accessibilityText(of: title), expectedTitle, file: file, line: line)
        return title
    }

    func accessibilityText(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    func waitUntil(
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        } while Date() < deadline
        let result = condition()
        XCTAssertTrue(result, "Condition did not become true within \(timeout) seconds", file: file, line: line)
        return result
    }

    @discardableResult
    func attachWindowScreenshot(
        _ name: String,
        application: XCUIApplication,
        appearance: PrismUITestAppearance,
        verifiesAppearance: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIScreenshot {
        let screenshot = requireMainWindow(in: application, file: file, line: line).screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(appearance.attachmentSlug)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let metrics = try screenshotMetrics(screenshot)
        XCTAssertGreaterThan(
            metrics.brightest,
            0.35,
            "The screenshot has no visible light content and may be hidden by screen privacy",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            metrics.luminanceRange,
            0.18,
            "The screenshot has too little visible UI structure",
            file: file,
            line: line
        )
        if verifiesAppearance {
            switch appearance {
            case .light:
                XCTAssertGreaterThan(metrics.average, 0.45, "Expected a light system surface", file: file, line: line)
            case .dark:
                XCTAssertLessThan(metrics.average, 0.45, "Expected a dark system surface", file: file, line: line)
            }
        }
        return screenshot
    }

    func attachAXHierarchy(of application: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: application.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func screenshotMetrics(_ screenshot: XCUIScreenshot) throws -> (
        average: Double,
        brightest: Double,
        luminanceRange: Double
    ) {
        let image = try XCTUnwrap(NSImage(data: screenshot.pngRepresentation))
        let data = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let stride = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 100)
        var total = 0.0
        var samples = 0
        var darkest = 1.0
        var brightest = 0.0

        for y in Swift.stride(from: 0, to: bitmap.pixelsHigh, by: stride) {
            for x in Swift.stride(from: 0, to: bitmap.pixelsWide, by: stride) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance = relativeLuminance(color)
                total += luminance
                samples += 1
                darkest = min(darkest, luminance)
                brightest = max(brightest, luminance)
            }
        }

        return (
            average: samples == 0 ? 0 : total / Double(samples),
            brightest: brightest,
            luminanceRange: brightest - darkest
        )
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

    private func safeAttachmentName(_ value: String) -> String {
        value.replacingOccurrences(of: ".", with: "-")
    }
}
