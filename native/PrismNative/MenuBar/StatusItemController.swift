import AppKit
import Observation

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
            let image = NSImage(systemSymbolName: "link", accessibilityDescription: "Prism")
            image?.isTemplate = true
            button.image = image
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
        menu.addItem(makeItem(title: "Open Prism", action: #selector(openPrism)))
        menu.addItem(makeItem(title: "History", action: #selector(openHistory)))
        menu.addItem(makeItem(title: "Rules", action: #selector(openRules)))
        menu.addItem(makeItem(title: "Browsers", action: #selector(openBrowsers)))
        menu.addItem(makeItem(title: "Settings", action: #selector(openSettings)))

        automaticRulesItem = makeItem(title: "", action: #selector(toggleAutomaticRules))
        menu.addItem(automaticRulesItem)

        checkForUpdatesItem = makeItem(
            title: "Check for Updates",
            action: #selector(checkForUpdates)
        )
        menu.addItem(checkForUpdatesItem)
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit Prism", action: #selector(quitPrism)))
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    private func synchronizeWithEnvironment() {
        automaticRulesItem.title = environment.settings.automaticRulesEnabled
            ? "Pause Automatic Rules"
            : "Resume Automatic Rules"
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
