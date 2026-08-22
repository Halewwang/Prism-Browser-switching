import AppKit
import PrismCore
import Testing
@testable import PrismNative

@Suite("Status item")
@MainActor
struct StatusItemControllerTests {
    @Test func installsTheExactMenuInTheRequiredOrder() async throws {
        let fixture = await StatusItemFixture.make(
            route: .history,
            automaticRulesEnabled: true,
            showMenuBarItem: true
        )

        _ = fixture.makeController()

        let menu = try #require(fixture.host.menu)
        #expect(menu.items.map(menuLabel) == [
            "Prism",
            "<separator>",
            "Open Prism",
            "History",
            "Rules",
            "Browsers",
            "Settings",
            "Pause Automatic Rules",
            "Check for Updates",
            "<separator>",
            "Quit Prism",
        ])
        #expect(menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil })
        #expect(menu.items[0].image?.isTemplate == true)
        #expect(fixture.host.installCount == 1)
        #expect(fixture.host.isVisible)
    }

    @Test func openPrismPreservesTheCurrentRouteAndEveryDestinationUsesTheSingletonWindowAdapter() async throws {
        let fixture = await StatusItemFixture.make(
            route: .rules,
            automaticRulesEnabled: true,
            showMenuBarItem: true
        )
        _ = fixture.makeController()
        let menu = try #require(fixture.host.menu)

        for index in 2...6 {
            try invokeItem(at: index, in: menu)
        }

        #expect(fixture.windows.routes == [
            .rules,
            .history,
            .rules,
            .browsers,
            .settings,
        ])
        #expect(fixture.windows.openedWindowIDs == ["main", "main", "main", "main", "main"])
        #expect(fixture.windows.openedValues == [
            .singleton,
            .singleton,
            .singleton,
            .singleton,
            .singleton,
        ])
        #expect(fixture.environment.route == .settings)
    }

    @Test func pauseAndResumeChangeOnlyTheDurableAutomaticRuleSetting() async throws {
        var settings = AppSettings.defaults
        settings.automaticRulesEnabled = true
        settings.showMenuBarItem = true
        settings.lastUsedBrowserID = "com.example.kept"
        settings.historyLimit = 321
        settings.language = .english
        let fixture = await StatusItemFixture.make(route: .history, settings: settings)
        _ = fixture.makeController()
        let menu = try #require(fixture.host.menu)

        try invokeItem(at: 7, in: menu)

        var expected = settings
        expected.automaticRulesEnabled = false
        #expect(try fixture.settingsRepository.load() == expected)
        #expect(fixture.environment.settings == expected)
        #expect(menu.items[7].title == "Resume Automatic Rules")
        #expect(fixture.updates.checkCount == 0)
        #expect(fixture.termination.count == 0)

        try invokeItem(at: 7, in: menu)

        #expect(try fixture.settingsRepository.load() == settings)
        #expect(fixture.environment.settings == settings)
        #expect(menu.items[7].title == "Pause Automatic Rules")
    }

    @Test func failedPauseSaveDoesNotFlipStateOrMenuLabel() async throws {
        let fixture = await StatusItemFixture.make(
            route: .history,
            automaticRulesEnabled: true,
            showMenuBarItem: true
        )
        _ = fixture.makeController()
        let menu = try #require(fixture.host.menu)
        fixture.settingsRepository.shouldFailSave = true

        try invokeItem(at: 7, in: menu)

        #expect(fixture.environment.settings.automaticRulesEnabled)
        #expect(try fixture.settingsRepository.load().automaticRulesEnabled)
        #expect(menu.items[7].title == "Pause Automatic Rules")
        #expect(fixture.environment.persistenceWarnings.contains(.settingsNotSaved))
    }

    @Test func checkForUpdatesInvokesTheInjectedCheckerWithoutReadingItsEventStream() async throws {
        let fixture = await StatusItemFixture.make(
            route: .history,
            automaticRulesEnabled: true,
            showMenuBarItem: true
        )
        _ = fixture.makeController()
        let menu = try #require(fixture.host.menu)

        try invokeItem(at: 8, in: menu)

        #expect(fixture.updates.checkCount == 1)
        #expect(fixture.updates.eventsReadCount == 0)
    }

    @Test func quitUsesOnlyTheInjectedTerminationAction() async throws {
        let fixture = await StatusItemFixture.make(
            route: .history,
            automaticRulesEnabled: true,
            showMenuBarItem: true
        )
        _ = fixture.makeController()
        let menu = try #require(fixture.host.menu)

        try invokeItem(at: 10, in: menu)

        #expect(fixture.termination.count == 1)
        #expect(fixture.windows.routes.isEmpty)
        #expect(fixture.updates.checkCount == 0)
    }

    @Test func visibilityTracksTheSharedMenuBarSetting() async {
        let fixture = await StatusItemFixture.make(
            route: .history,
            automaticRulesEnabled: true,
            showMenuBarItem: true
        )
        let controller = fixture.makeController()
        #expect(fixture.host.isVisible)

        #expect(fixture.environment.mutateSettings { $0.showMenuBarItem = false })
        await waitUntil { !fixture.host.isVisible }
        #expect(!fixture.host.isVisible)

        #expect(fixture.environment.mutateSettings { $0.showMenuBarItem = true })
        await waitUntil { fixture.host.isVisible }
        #expect(fixture.host.isVisible)

        _ = controller
    }

    @Test func prismMenuBarMarkIsAnAccessibleTemplateImage() {
        let image = StatusItemVisuals.prismMark()

        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
        #expect(image.accessibilityDescription == "Prism")
    }

    @Test func menuUsesTheSelectedAppLanguage() async throws {
        var settings = AppSettings.defaults
        settings.language = .simplifiedChinese
        settings.automaticRulesEnabled = true
        settings.showMenuBarItem = true
        let fixture = await StatusItemFixture.make(route: .history, settings: settings)

        _ = fixture.makeController()

        let menu = try #require(fixture.host.menu)
        #expect(menu.items[2].title == "打开 Prism")
        #expect(menu.items[7].title == "暂停自动规则")
    }

    private func menuLabel(_ item: NSMenuItem) -> String {
        item.isSeparatorItem ? "<separator>" : item.title
    }

    private func invokeItem(at index: Int, in menu: NSMenu) throws {
        let item = menu.items[index]
        let action = try #require(item.action)
        #expect(NSApplication.shared.sendAction(action, to: item.target, from: item))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }
}

@MainActor
private final class StatusItemFixture {
    let environment: AppEnvironment
    let settingsRepository: StatusItemSettingsRepository
    let host = RecordingStatusItemHost()
    let windows = RecordingMainWindowOpening()
    let updates = RecordingUpdateChecker()
    let termination = TerminationRecorder()
    private var retainedController: StatusItemController?

    private init(
        environment: AppEnvironment,
        settingsRepository: StatusItemSettingsRepository
    ) {
        self.environment = environment
        self.settingsRepository = settingsRepository
    }

    static func make(
        route: AppRoute,
        automaticRulesEnabled: Bool,
        showMenuBarItem: Bool
    ) async -> StatusItemFixture {
        var settings = AppSettings.defaults
        settings.automaticRulesEnabled = automaticRulesEnabled
        settings.showMenuBarItem = showMenuBarItem
        settings.language = .english
        return await make(route: route, settings: settings)
    }

    static func make(route: AppRoute, settings: AppSettings) async -> StatusItemFixture {
        let repository = StatusItemSettingsRepository(settings: settings)
        let environment = AppEnvironment(
            route: route,
            unmatchedBehavior: settings.unmatchedBehavior,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: InMemoryRuleRepository(),
            historyRepository: InMemoryHistoryRepository(),
            browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
            settingsRepository: repository
        )
        let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
        let restored = await environment.restoreAndReconcile(queue: queue, warningSource: nil)
        precondition(restored)
        return StatusItemFixture(environment: environment, settingsRepository: repository)
    }

    func makeController() -> StatusItemController {
        let opening = MainWindowOpening { [environment, windows] route in
            environment.updateRoute(route)
            windows.routes.append(route)
        }
        opening.register { [windows] id, value in
            windows.openedWindowIDs.append(id)
            windows.openedValues.append(value)
        }
        let controller = StatusItemController(
            host: host,
            mainWindowOpening: opening,
            environment: environment,
            updateChecker: updates,
            terminate: { [termination] in termination.count += 1 }
        )
        retainedController = controller
        return controller
    }
}

@MainActor
private final class RecordingStatusItemHost: StatusItemHosting {
    private(set) var menu: NSMenu?
    private(set) var installCount = 0
    private(set) var isVisible = false

    func install(menu: NSMenu) {
        self.menu = menu
        installCount += 1
    }

    func setVisible(_ isVisible: Bool) {
        self.isVisible = isVisible
    }
}

@MainActor
private final class RecordingMainWindowOpening {
    var routes: [AppRoute] = []
    var openedWindowIDs: [String] = []
    var openedValues: [MainWindowIdentity] = []
}

@MainActor
private final class RecordingUpdateChecker: UpdateChecking {
    private let stream: AsyncStream<UpdateEvent>
    private(set) var eventsReadCount = 0
    private(set) var checkCount = 0

    var events: AsyncStream<UpdateEvent> {
        eventsReadCount += 1
        return stream
    }

    let canCheckForUpdates = true
    var automaticallyChecksForUpdates = false

    init() {
        stream = AsyncStream { _ in }
    }

    func checkForUpdates() {
        checkCount += 1
    }
}

@MainActor
private final class TerminationRecorder {
    var count = 0
}

@MainActor
private final class StatusItemSettingsRepository: SettingsRepository {
    private enum Failure: Error {
        case save
    }

    private var settings: AppSettings
    var shouldFailSave = false

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() throws -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) throws {
        if shouldFailSave {
            throw Failure.save
        }
        self.settings = settings
    }
}
