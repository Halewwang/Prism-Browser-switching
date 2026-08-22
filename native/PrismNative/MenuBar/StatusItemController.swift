import AppKit
import Observation

enum StatusItemVisuals {
    static func prismMark() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setStroke()
        let mark = NSBezierPath()
        mark.lineWidth = 2.8
        mark.lineCapStyle = .square
        mark.move(to: NSPoint(x: 9, y: 2))
        mark.line(to: NSPoint(x: 9, y: 16))
        mark.move(to: NSPoint(x: 2, y: 9))
        mark.line(to: NSPoint(x: 16, y: 9))
        mark.move(to: NSPoint(x: 3.5, y: 3.5))
        mark.line(to: NSPoint(x: 14.5, y: 14.5))
        mark.move(to: NSPoint(x: 3.5, y: 14.5))
        mark.line(to: NSPoint(x: 14.5, y: 3.5))
        mark.stroke()
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Prism"
        return image
    }

    static func menuSymbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }
}

@MainActor
protocol StatusItemHosting: AnyObject {
    func install(menu: NSMenu)
    func setVisible(_ isVisible: Bool)
}

@MainActor
final class AppKitStatusItemHost: StatusItemHosting {
    private let statusItem: NSStatusItem

    init(statusBar: NSStatusBar = .system) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusItemVisuals.prismMark()
            button.toolTip = "Prism"
        }
    }

    func install(menu: NSMenu) {
        statusItem.menu = menu
    }

    func setVisible(_ isVisible: Bool) {
        statusItem.isVisible = isVisible
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let host: any StatusItemHosting
    private let mainWindowOpening: MainWindowOpening
    private let environment: AppEnvironment
    private let updateChecker: any UpdateChecking
    private let terminate: @MainActor () -> Void
    private let menu = NSMenu(title: "Prism")
    private var automaticRulesItem: NSMenuItem!
    private var checkForUpdatesItem: NSMenuItem!

    init(
        host: any StatusItemHosting = AppKitStatusItemHost(),
        mainWindowOpening: MainWindowOpening,
        environment: AppEnvironment,
        updateChecker: any UpdateChecking,
        terminate: @escaping @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.host = host
        self.mainWindowOpening = mainWindowOpening
        self.environment = environment
        self.updateChecker = updateChecker
        self.terminate = terminate
        super.init()

        configureMenu()
        synchronizeWithEnvironment()
        observeSettings()
        host.install(menu: menu)
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "Prism", action: nil, keyEquivalent: "")
        header.image = StatusItemVisuals.prismMark()
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Open Prism", action: #selector(openPrism), symbol: "rectangle.on.rectangle"))
        menu.addItem(makeItem(title: "History", action: #selector(openHistory), symbol: "clock.arrow.circlepath"))
        menu.addItem(makeItem(title: "Rules", action: #selector(openRules), symbol: "list.bullet.rectangle"))
        menu.addItem(makeItem(title: "Browsers", action: #selector(openBrowsers), symbol: "safari"))
        menu.addItem(makeItem(title: "Settings", action: #selector(openSettings), symbol: "gearshape"))

        automaticRulesItem = makeItem(title: "", action: #selector(toggleAutomaticRules), symbol: "pause.circle")
        menu.addItem(automaticRulesItem)

        checkForUpdatesItem = makeItem(
            title: "Check for Updates",
            action: #selector(checkForUpdates),
            symbol: "arrow.clockwise"
        )
        menu.addItem(checkForUpdatesItem)
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit Prism", action: #selector(quitPrism), symbol: "power"))
    }

    private func makeItem(title: String, action: Selector, symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = StatusItemVisuals.menuSymbol(symbol)
        item.isEnabled = true
        return item
    }

    private func synchronizeWithEnvironment() {
        automaticRulesItem.title = environment.settings.automaticRulesEnabled
            ? "Pause Automatic Rules"
            : "Resume Automatic Rules"
        automaticRulesItem.image = StatusItemVisuals.menuSymbol(
            environment.settings.automaticRulesEnabled ? "pause.circle" : "play.circle"
        )
        checkForUpdatesItem.isEnabled = updateChecker.canCheckForUpdates
        host.setVisible(environment.settings.showMenuBarItem)
    }

    private func observeSettings() {
        withObservationTracking {
            _ = environment.settings.automaticRulesEnabled
            _ = environment.settings.showMenuBarItem
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.synchronizeWithEnvironment()
                self.observeSettings()
            }
        }
    }

    @objc private func openPrism() {
        mainWindowOpening.open(route: environment.route)
    }

    @objc private func openHistory() {
        mainWindowOpening.open(route: .history)
    }

    @objc private func openRules() {
        mainWindowOpening.open(route: .rules)
    }

    @objc private func openBrowsers() {
        mainWindowOpening.open(route: .browsers)
    }

    @objc private func openSettings() {
        mainWindowOpening.open(route: .settings)
    }

    @objc private func toggleAutomaticRules() {
        let nextValue = !environment.settings.automaticRulesEnabled
        guard environment.mutateSettings({ $0.automaticRulesEnabled = nextValue }) else {
            return
        }
        synchronizeWithEnvironment()
    }

    @objc private func checkForUpdates() {
        updateChecker.checkForUpdates()
    }

    @objc private func quitPrism() {
        terminate()
    }
}
