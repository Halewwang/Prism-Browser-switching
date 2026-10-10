import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func appEnvironmentLoadsDurableSettingsExactlyOnceDuringRestore() async {
    var durable = AppSettings.defaults
    durable.language = .english
    durable.unmatchedBehavior = .lastUsedBrowser
    durable.historyLimit = 42
    let repository = RecordingSettingsRepository(settings: durable)

    let environment = makeEnvironment(
        unmatchedBehavior: .preferredBrowser,
        settingsRepository: repository
    )
    #expect(repository.loadCount == 0)
    #expect(environment.unmatchedBehavior == .preferredBrowser)

    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))

    #expect(repository.loadCount == 1)
    #expect(environment.settings == durable)
    #expect(environment.unmatchedBehavior == .lastUsedBrowser)
    #expect(!environment.persistenceWarnings.contains(.settingsNotSaved))
}

@Test @MainActor func appEnvironmentUsesRequestedBehaviorBeforeRestoreAndAlwaysAskAfterLoadFailure() async {
    let repository = RecordingSettingsRepository(
        settings: .defaults,
        shouldFailLoad: true
    )

    let environment = makeEnvironment(
        unmatchedBehavior: .preferredBrowser,
        settingsRepository: repository
    )

    #expect(repository.loadCount == 0)
    #expect(environment.unmatchedBehavior == .preferredBrowser)
    #expect(!environment.persistenceWarnings.contains(.settingsNotSaved))

    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))

    #expect(repository.loadCount == 1)
    #expect(environment.unmatchedBehavior == .alwaysAsk)
    #expect(environment.settings.unmatchedBehavior == .alwaysAsk)
    #expect(environment.settings.historyEnabled == false)
    #expect(environment.settings.historyLimit == 0)
    #expect(environment.settings.automaticRulesEnabled == false)
    #expect(environment.persistenceWarnings.contains(.settingsNotSaved))
}

@Test @MainActor func settingsMutationMergesAnExternalLastUsedBrowserUpdate() throws {
    let repository = RecordingSettingsRepository(settings: .defaults)
    let environment = makeEnvironment(settingsRepository: repository)
    let externallySelectedBrowser = BrowserID("com.example.external")
    repository.updateDurableSettings {
        $0.lastUsedBrowserID = externallySelectedBrowser
    }

    #expect(environment.mutateSettings { $0.showMenuBarItem = false })

    let durable = try repository.load()
    #expect(durable.lastUsedBrowserID == externallySelectedBrowser)
    #expect(durable.showMenuBarItem == false)
    #expect(environment.settings == durable)
    #expect(repository.loadCount == 2)
}

@Test @MainActor func settingsWarningClearsOnlyAfterASuccessfulSave() async {
    let repository = RecordingSettingsRepository(settings: .defaults)
    let environment = makeEnvironment(
        settingsRepository: repository,
        persistenceWarnings: [.settingsNotSaved]
    )
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())

    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))
    #expect(environment.persistenceWarnings.contains(.settingsNotSaved))

    #expect(environment.mutateSettings { $0.showMenuBarItem = false })
    #expect(!environment.persistenceWarnings.contains(.settingsNotSaved))
}

@Test @MainActor func failedSettingsSaveDoesNotFlipObservableStateAndSuccessfulRetryClearsWarning() throws {
    let repository = RecordingSettingsRepository(settings: .defaults)
    let environment = makeEnvironment(settingsRepository: repository)
    let initialSettings = environment.settings
    let durableSettings = try repository.load()

    repository.shouldFailSave = true
    #expect(!environment.mutateSettings { $0.onboardingCompleted = true })
    #expect(environment.settings == initialSettings)
    #expect(environment.unmatchedBehavior == initialSettings.unmatchedBehavior)
    #expect(try repository.load() == durableSettings)
    #expect(environment.persistenceWarnings.contains(.settingsNotSaved))

    repository.shouldFailSave = false
    #expect(environment.mutateSettings { $0.onboardingCompleted = true })
    #expect(environment.settings.onboardingCompleted)
    #expect(!environment.persistenceWarnings.contains(.settingsNotSaved))
}

@Test @MainActor func advanceFromLinkHandlingOnlyRequeriesCurrentStatus() async {
    let fixture = OnboardingFixture(
        handlerState: .inactive(http: false, https: false),
        browsers: [onboardingBrowser]
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()

    #expect(fixture.defaultHandlerClient.setRequests.isEmpty)
    #expect(model.step == .linkHandling)
    #expect(model.alert == .defaultHandlerIncomplete)
}

@Test @MainActor func welcomeAdvanceChecksHandlerBeforeExposingItsStatus() async {
    let fixture = OnboardingFixture(
        handlerState: .inactive(http: true, https: false),
        browsers: [onboardingBrowser]
    )
    let model = fixture.model

    #expect(!model.handlerStatusIsKnown)
    #expect(!model.isCheckingHandlers)

    await model.advanceFromWelcome()

    #expect(model.step == .linkHandling)
    #expect(model.handlerStatusIsKnown)
    #expect(!model.isCheckingHandlers)
    #expect(model.httpHandlerIsActive)
    #expect(!model.httpsHandlerIsActive)
    #expect(model.alert == .defaultHandlerIncomplete)
}

@Test @MainActor func explicitDefaultActionSetsBothSchemesThenRequeriesActualStatus() async {
    let fixture = OnboardingFixture(
        handlerState: .inactive(http: false, https: false),
        browsers: [onboardingBrowser]
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    await model.setPrismAsDefault()

    #expect(fixture.defaultHandlerClient.setRequests == ["http", "https"])
    #expect(model.httpHandlerIsActive)
    #expect(model.httpsHandlerIsActive)
    #expect(model.step == .browsers)
    #expect(model.alert == nil)
}

@Test @MainActor func partialDefaultActionFailureStaysOnLinkHandlingWithActualStatus() async {
    let fixture = OnboardingFixture(
        handlerState: .inactive(http: false, https: false),
        browsers: [onboardingBrowser],
        failingDefaultSchemes: ["https"]
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    await model.setPrismAsDefault()

    #expect(fixture.defaultHandlerClient.setRequests == ["http", "https"])
    #expect(model.httpHandlerIsActive)
    #expect(!model.httpsHandlerIsActive)
    #expect(model.step == .linkHandling)
    #expect(model.alert == .defaultHandlerIncomplete)
}

@Test @MainActor func finishLaterFromLinkHandlingOnlyAdvancesToBrowserSelection() async throws {
    let fixture = OnboardingFixture(
        handlerState: .inactive(http: false, https: false),
        browsers: [onboardingBrowser]
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    model.finishLater()

    #expect(model.step == .browsers)
    #expect(try !fixture.settingsRepository.load().onboardingCompleted)
    #expect(fixture.recorder.openedRoutes.isEmpty)
}

@Test @MainActor func finishLaterCannotBypassWelcomeOrBrowserSelection() async {
    let fixture = OnboardingFixture(
        handlerState: .active,
        browsers: [onboardingBrowser]
    )
    let model = fixture.model

    model.finishLater()
    #expect(model.step == .welcome)

    await model.advanceFromWelcome()
    model.finishLater()
    #expect(model.step == .browsers)

    model.finishLater()
    #expect(model.step == .browsers)
    #expect(fixture.recorder.openedRoutes.isEmpty)
}

@Test @MainActor func enteringTestLinkPersistsAlwaysAskBeforeAdvancing() async throws {
    var settings = AppSettings.defaults
    settings.unmatchedBehavior = .preferredBrowser
    let fixture = OnboardingFixture(
        handlerState: .active,
        browsers: [onboardingBrowser],
        settings: settings
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()
    await model.advanceFromBrowserScan()

    #expect(model.step == .testLink)
    #expect(model.alert == nil)
    #expect(try fixture.settingsRepository.load().unmatchedBehavior == .alwaysAsk)
    #expect(fixture.environment.unmatchedBehavior == .alwaysAsk)
    #expect(await fixture.queue.snapshot().isEmpty)
}

@Test @MainActor func settingsSaveFailureKeepsBrowserGateAndDoesNotStartTest() async {
    var settings = AppSettings.defaults
    settings.unmatchedBehavior = .preferredBrowser
    let fixture = OnboardingFixture(
        handlerState: .active,
        browsers: [onboardingBrowser],
        settings: settings
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()
    fixture.settingsRepository.shouldFailSave = true
    await model.advanceFromBrowserScan()
    await model.beginTestLink()

    #expect(model.step == .browsers)
    #expect(model.alert == .settingsNotSaved)
    #expect(fixture.environment.unmatchedBehavior == .preferredBrowser)
    #expect(await fixture.queue.snapshot().isEmpty)

    fixture.settingsRepository.shouldFailSave = false
    await model.advanceFromBrowserScan()

    #expect(model.step == .testLink)
    #expect(model.alert == nil)
    #expect(fixture.environment.unmatchedBehavior == .alwaysAsk)
}

@Test @MainActor func finishTestLaterCompletesOnlyFromTestLinkAfterSaving() async throws {
    let fixture = OnboardingFixture(
        handlerState: .active,
        browsers: [onboardingBrowser]
    )
    let model = fixture.model

    await model.finishTestLater()
    #expect(model.step == .welcome)

    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()
    await model.advanceFromBrowserScan()
    await model.finishTestLater()

    #expect(model.step == .testLink)
    #expect(try fixture.settingsRepository.load().onboardingCompleted)
    #expect(fixture.recorder.openedRoutes == [.history])
}

@Test @MainActor func completionSaveFailureRemainsAtTestLink() async throws {
    let fixture = OnboardingFixture(
        handlerState: .active,
        browsers: [onboardingBrowser]
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()
    await model.advanceFromBrowserScan()
    fixture.settingsRepository.shouldFailSave = true
    await model.finishTestLater()

    #expect(model.step == .testLink)
    #expect(model.alert == .settingsNotSaved)
    #expect(model.completionSaveIsPending)
    #expect(try !fixture.settingsRepository.load().onboardingCompleted)
    #expect(fixture.recorder.openedRoutes.isEmpty)

    fixture.settingsRepository.shouldFailSave = false
    await model.finishTestLater()

    #expect(try fixture.settingsRepository.load().onboardingCompleted)
    #expect(!model.completionSaveIsPending)
    #expect(fixture.recorder.openedRoutes == [.history])
}

@Test @MainActor func acceptedTestCanBeRepeatedBeforeExplicitlyCompletingSetup() async throws {
    let fixture = OnboardingFixture(handlerState: .active, browsers: [onboardingBrowser])
    let model = fixture.model
    await model.advanceFromWelcome()
    await model.advanceFromBrowserScan()
    await model.finishSetup()
    #expect(fixture.recorder.openedRoutes.isEmpty)
    await model.beginTestLink()
    let first = try #require(await fixture.queue.snapshot().first)
    await fixture.routingCoordinator.select(browserID: onboardingBrowser.id, for: first.id)
    #expect(model.testLinkWasAccepted)
    #expect(!fixture.environment.settings.onboardingCompleted)
    #expect(fixture.recorder.openedRoutes.isEmpty)

    await model.beginTestLink()
    let second = try #require(await fixture.queue.snapshot().first)
    #expect(second.id != first.id)
    #expect(!model.testLinkWasAccepted)
    #expect(model.isTestLinkInProgress)
    await fixture.routingCoordinator.select(browserID: onboardingBrowser.id, for: second.id)

    #expect(model.testLinkWasAccepted)
    await model.finishSetup()
    await model.finishSetup()
    #expect(try fixture.settingsRepository.load().onboardingCompleted)
    #expect(fixture.recorder.openedRoutes == [.history])
    #expect(fixture.recorder.resumeRoutingCount == 1)
}

@Test @MainActor func rescanRemainsAvailableAtTheIdleTestStepButDoesNotInterruptAnActiveTest() async throws {
    let fixture = OnboardingFixture(handlerState: .active, browsers: [onboardingBrowser])
    let model = fixture.model
    await model.advanceFromWelcome()
    await model.advanceFromBrowserScan()
    fixture.settingsRepository.updateDurableSettings { $0.unmatchedBehavior = .preferredBrowser }
    await model.advanceFromBrowserScan()
    #expect(try fixture.settingsRepository.load().unmatchedBehavior == .alwaysAsk)
    #expect(model.step == .testLink)

    await model.beginTestLink()
    let requestIDs = await fixture.queue.snapshot().map(\.id)
    await model.advanceFromBrowserScan()
    #expect(model.isTestLinkInProgress)
    #expect(await fixture.queue.snapshot().map(\.id) == requestIDs)
}

@Test @MainActor func browserScanFiltersUnavailableApplications() async {
    let unavailable = makeOnboardingBrowser(
        id: "com.example.unavailable",
        availability: .unavailable
    )
    let fixture = OnboardingFixture(
        handlerState: .active,
        browsers: [unavailable, onboardingBrowser]
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()
    await model.advanceFromBrowserScan()

    #expect(model.step == .testLink)
    #expect(model.usableBrowsers.map(\.id) == [onboardingBrowser.id])
}

@Test @MainActor func browserScanWithNoAvailableApplicationsShowsNoUsableBrowser() async {
    let fixture = OnboardingFixture(
        handlerState: .active,
        browsers: [makeOnboardingBrowser(id: "com.example.missing", availability: .unavailable)]
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()
    await model.advanceFromBrowserScan()

    #expect(model.step == .browsers)
    #expect(model.usableBrowsers.isEmpty)
    #expect(model.alert == .noUsableBrowser)
}

@Test @MainActor func thrownBrowserScanShowsScanFailure() async {
    let fixture = OnboardingFixture(
        handlerState: .active,
        browsers: [onboardingBrowser],
        browserScanFails: true
    )
    let model = fixture.model

    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()
    await model.advanceFromBrowserScan()

    #expect(model.step == .browsers)
    #expect(model.usableBrowsers.isEmpty)
    #expect(model.alert == .browserScanFailed)
}

@Test @MainActor func repeatedDestinationsUseTheSingletonMainWindowIdentity() {
    var route = AppRoute.history
    var openings: [(String, MainWindowIdentity)] = []
    let opening = MainWindowOpening { route = $0 }
    opening.register { id, value in openings.append((id, value)) }

    opening.open(route: .history)
    opening.open(route: .settings)
    opening.open(route: route)

    #expect(route == .settings)
    #expect(openings.count == 3)
    #expect(openings.allSatisfy { $0.0 == "main" && $0.1 == .singleton })
}

@Test @MainActor func routingOutcomesAreScopedToTheExactRequestAndCarryNoLink() async {
    let watchedRequestID = UUID()
    let unrelatedRequestID = UUID()
    let center = LinkRoutingOutcomeCenter()
    var received: [LinkRoutingOutcome] = []
    center.observe(requestID: watchedRequestID) { outcome in
        received.append(outcome)
        return true
    }

    await center.report(LinkRoutingOutcome(
        requestID: unrelatedRequestID,
        kind: .handoffAccepted
    ))
    #expect(received.isEmpty)

    await center.report(LinkRoutingOutcome(
        requestID: watchedRequestID,
        kind: .handoffFailed
    ))
    #expect(received == [LinkRoutingOutcome(
        requestID: watchedRequestID,
        kind: .handoffFailed
    )])
}

@MainActor
private struct OnboardingFixture {
    let model: OnboardingViewModel
    let environment: AppEnvironment
    let settingsRepository: RecordingSettingsRepository
    let defaultHandlerClient: MutableDefaultHandlerClient
    let recorder: OnboardingRecorder
    let queue: LinkRequestQueue
    let routingCoordinator: LinkRoutingCoordinator
    let testLinkRouter: OnboardingTestLinkRouter

    init(
        handlerState: DefaultHandlerState,
        browsers: [BrowserDescriptor],
        settings: AppSettings = .defaults,
        failingDefaultSchemes: Set<String> = [],
        browserScanFails: Bool = false
    ) {
        settingsRepository = RecordingSettingsRepository(settings: settings)
        environment = makeEnvironment(
            unmatchedBehavior: settings.unmatchedBehavior,
            settingsRepository: settingsRepository
        )
        defaultHandlerClient = MutableDefaultHandlerClient(
            state: handlerState,
            failingSchemes: failingDefaultSchemes
        )
        recorder = OnboardingRecorder()
        queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
        let outcomeCenter = LinkRoutingOutcomeCenter()
        let catalog = FixedOnboardingBrowserCatalog(
            browsers: browsers,
            shouldFail: browserScanFails
        )
        let presenter = RecordingOnboardingSelectionPresenter()
        routingCoordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: environment.ruleRepository,
            historyRepository: environment.historyRepository,
            settingsRepository: settingsRepository,
            browserCatalog: catalog,
            browserLauncher: RecordingOnboardingBrowserLauncher(),
            sourceManifest: .disabled,
            presenter: presenter,
            warningPresenter: environment,
            outcomeReporter: outcomeCenter
        )
        let intake = LinkIntakeService(
            queue: queue,
            bootstrap: BootstrapLinkBuffer(),
            sourceAttributor: OnboardingUnknownSourceAttributor(),
            lastActivatedSource: { nil },
            coordinator: routingCoordinator,
            warningPresenter: environment
        )
        routingCoordinator.continuationRequester = intake
        intake.finishRestorationAndStartDraining(routeAfterDraining: false)
        testLinkRouter = OnboardingTestLinkRouter(
            intake: intake,
            coordinator: routingCoordinator,
            outcomes: outcomeCenter
        )
        model = OnboardingViewModel(
            environment: environment,
            defaultBrowserService: DefaultBrowserService(
                client: defaultHandlerClient,
                applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
                bundleIdentifier: "com.prism.app"
            ),
            browserCatalog: catalog,
            testLinkRouter: testLinkRouter,
            openMainWindow: { [recorder] route in recorder.openedRoutes.append(route) },
            resumeRouting: { [recorder] in recorder.resumeRoutingCount += 1 }
        )
    }
}

@MainActor
private func makeEnvironment(
    unmatchedBehavior: UnmatchedBehavior = .alwaysAsk,
    settingsRepository: any SettingsRepository,
    persistenceWarnings: [PersistenceWarning] = []
) -> AppEnvironment {
    AppEnvironment(
        route: .history,
        unmatchedBehavior: unmatchedBehavior,
        updateChecker: DisabledUpdateChecker(),
        ruleRepository: InMemoryRuleRepository(),
        historyRepository: InMemoryHistoryRepository(),
        browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
        settingsRepository: settingsRepository,
        persistenceWarnings: persistenceWarnings
    )
}

@MainActor
private final class MutableDefaultHandlerClient: DefaultHandlerClient {
    private var httpIsActive: Bool
    private var httpsIsActive: Bool
    private let failingSchemes: Set<String>
    private(set) var setRequests: [String] = []

    init(state: DefaultHandlerState, failingSchemes: Set<String>) {
        switch state {
        case .active:
            httpIsActive = true
            httpsIsActive = true
        case let .inactive(http, https):
            httpIsActive = http
            httpsIsActive = https
        }
        self.failingSchemes = failingSchemes
    }

    func handlerBundleIdentifier(forScheme scheme: String) -> String? {
        let isActive = scheme == "http" ? httpIsActive : httpsIsActive
        return isActive ? "com.prism.app" : "com.example.other"
    }

    func setDefault(applicationURL _: URL, forScheme scheme: String) async throws {
        setRequests.append(scheme)
        guard !failingSchemes.contains(scheme) else {
            throw OnboardingFixtureError.defaultRegistrationFailed
        }
        if scheme == "http" {
            httpIsActive = true
        } else if scheme == "https" {
            httpsIsActive = true
        }
    }
}

@MainActor
private final class FixedOnboardingBrowserCatalog: BrowserCataloging {
    private let browsers: [BrowserDescriptor]
    private let shouldFail: Bool

    init(browsers: [BrowserDescriptor], shouldFail: Bool) {
        self.browsers = browsers
        self.shouldFail = shouldFail
    }

    func scan() async throws -> [BrowserDescriptor] {
        if shouldFail { throw OnboardingFixtureError.browserScanFailed }
        return browsers
    }
}

@MainActor
private final class RecordingSettingsRepository: SettingsRepository {
    private var storedSettings: AppSettings
    private(set) var loadCount = 0
    var shouldFailLoad: Bool
    var shouldFailSave: Bool

    init(
        settings: AppSettings,
        shouldFailLoad: Bool = false,
        shouldFailSave: Bool = false
    ) {
        storedSettings = settings
        self.shouldFailLoad = shouldFailLoad
        self.shouldFailSave = shouldFailSave
    }

    func load() throws -> AppSettings {
        loadCount += 1
        if shouldFailLoad { throw OnboardingFixtureError.settingsLoadFailed }
        return storedSettings
    }

    func save(_ settings: AppSettings) throws {
        if shouldFailSave { throw OnboardingFixtureError.settingsSaveFailed }
        storedSettings = settings
    }

    func updateDurableSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&storedSettings)
    }
}

@MainActor
private final class OnboardingRecorder {
    var openedRoutes: [AppRoute] = []
    var resumeRoutingCount = 0
}

@MainActor
private final class RecordingOnboardingSelectionPresenter: LinkSelectionPresenting {
    func present(_: LinkRequest, context _: SelectorPresentationContext) {}
    func dismiss(requestID _: UUID) {}
}

@MainActor
private final class RecordingOnboardingBrowserLauncher: BrowserLaunching {
    func open(_: URL, with _: BrowserDescriptor) async throws -> BrowserLaunchResult {
        .handoffSucceeded
    }
}

@MainActor
private struct OnboardingUnknownSourceAttributor: SourceAttributing {
    func resolve(senderPID _: Int32?, lastActivated _: SourceApplication?) -> SourceApplication {
        .unknown
    }
}

private enum OnboardingFixtureError: Error {
    case defaultRegistrationFailed
    case browserScanFailed
    case settingsLoadFailed
    case settingsSaveFailed
}

private let onboardingBrowser = makeOnboardingBrowser(
    id: "com.example.browser",
    availability: .available
)

private func makeOnboardingBrowser(
    id: String,
    availability: BrowserAvailability
) -> BrowserDescriptor {
    BrowserDescriptor(
        id: BrowserID(id),
        bundleIdentifier: id,
        displayName: "Fixture Browser",
        applicationURL: URL(fileURLWithPath: "/Applications/Fixture Browser.app"),
        securityScopedBookmark: nil,
        origin: .system,
        availability: availability,
        selectorOrder: 0
    )
}
