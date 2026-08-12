import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func onboardingTestLinkUsesRealIntakeSelectorCoordinatorAndAcceptedHandoff() async throws {
    let fixture = OnboardingRoutingFixture(launchOutcomes: [.success])
    var outcomes: [LinkRoutingOutcome] = []

    let session = await fixture.router.start(
        url: onboardingRoutingURL,
        onPrepared: { _ in true }
    ) { outcome in
        outcomes.append(outcome)
        return true
    }
    #expect(session != nil)

    let request = try #require(fixture.presenter.request)
    #expect(request.url == onboardingRoutingURL)
    #expect(outcomes.isEmpty)
    #expect(fixture.launcher.openedURLs.isEmpty)

    await fixture.coordinator.select(browserID: onboardingRoutingBrowser.id, for: request.id)

    #expect(fixture.launcher.openedURLs == [onboardingRoutingURL])
    #expect(outcomes == [LinkRoutingOutcome(requestID: request.id, kind: .handoffAccepted)])
    #expect(await fixture.queue.terminalSnapshot().isEmpty)
}

@Test @MainActor func onboardingTestLinkFailureStaysObservedUntilRealRetrySucceeds() async throws {
    let fixture = OnboardingRoutingFixture(launchOutcomes: [.failure, .success])
    var outcomes: [LinkRoutingOutcome] = []

    let session = await fixture.router.start(
        url: onboardingRoutingURL,
        onPrepared: { _ in true }
    ) { outcome in
        outcomes.append(outcome)
        return true
    }
    #expect(session != nil)
    let request = try #require(fixture.presenter.request)

    await fixture.coordinator.select(browserID: onboardingRoutingBrowser.id, for: request.id)

    #expect(outcomes == [LinkRoutingOutcome(requestID: request.id, kind: .handoffFailed)])
    #expect((await fixture.queue.snapshot()).map(\.state) == [.presenting])

    await fixture.coordinator.retry(browserID: onboardingRoutingBrowser.id, for: request.id)

    #expect(fixture.launcher.openedURLs == [onboardingRoutingURL, onboardingRoutingURL])
    #expect(outcomes == [
        LinkRoutingOutcome(requestID: request.id, kind: .handoffFailed),
        LinkRoutingOutcome(requestID: request.id, kind: .handoffAccepted)
    ])
}

@Test @MainActor func onboardingTestLinkRefusesToOvertakeAnExistingRealRequest() async throws {
    let fixture = OnboardingRoutingFixture(launchOutcomes: [.success])
    let existing = LinkRequest.fixture(url: "https://existing-user-request.example/private")
    #expect(try await fixture.queue.enqueue(existing))
    var outcomes: [LinkRoutingOutcome] = []

    let session = await fixture.router.start(
        url: onboardingRoutingURL,
        onPrepared: { _ in true }
    ) { outcome in
        outcomes.append(outcome)
        return true
    }

    #expect(session == nil)
    #expect((await fixture.queue.snapshot()).map(\.id) == [existing.id])
    #expect(fixture.presenter.request == nil)
    #expect(fixture.launcher.openedURLs.isEmpty)
    #expect(outcomes.isEmpty)
}

@Test @MainActor func releasingATestLinkSessionRemovesItsExactOutcomeObservation() async throws {
    let fixture = OnboardingRoutingFixture(launchOutcomes: [.success])
    var outcomes: [LinkRoutingOutcome] = []
    var session = await fixture.router.start(
        url: onboardingRoutingURL,
        onPrepared: { _ in true }
    ) { outcome in
        outcomes.append(outcome)
        return true
    }
    let requestID = try #require(session?.requestID)

    session = nil
    await fixture.outcomes.report(LinkRoutingOutcome(
        requestID: requestID,
        kind: .handoffAccepted
    ))

    #expect(outcomes.isEmpty)
}

@Test @MainActor func modelOwnsTheExactSessionBeforePresentationCanReportAccepted() async throws {
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    let outcomes = LinkRoutingOutcomeCenter()
    let coordinator = ReentrantAcceptedOnboardingCoordinator(
        queue: queue,
        outcomes: outcomes
    )
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: BootstrapLinkBuffer(),
        sourceAttributor: OnboardingRoutingSourceAttributor(),
        lastActivatedSource: { nil },
        coordinator: coordinator
    )
    coordinator.continuationRequester = intake
    intake.finishRestorationAndStartDraining(routeAfterDraining: false)
    await intake.waitForPersistenceForTesting()
    let settings = OnboardingRoutingSettingsRepository(settings: .defaults, saveFails: false)
    let environment = makeOnboardingRoutingEnvironment(settings: settings)
    let recorder = OnboardingModelRecorder()
    let model = OnboardingViewModel(
        environment: environment,
        defaultBrowserService: DefaultBrowserService(
            client: ActiveOnboardingDefaultHandlerClient(),
            applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
            bundleIdentifier: "com.prism.app"
        ),
        browserCatalog: OnboardingRoutingCatalog(),
        testLinkRouter: OnboardingTestLinkRouter(
            intake: intake,
            coordinator: coordinator,
            outcomes: outcomes
        ),
        openMainWindow: { [recorder] route in recorder.openedRoutes.append(route) },
        resumeRouting: { [recorder] in recorder.resumeCount += 1 }
    )
    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()
    await model.advanceFromBrowserScan()

    await model.beginTestLink()

    #expect(coordinator.presentedRequestIDs.count == 1)
    #expect(environment.settings.onboardingCompleted)
    #expect(!model.isTestLinkInProgress)
    #expect(model.alert == nil)
    #expect(recorder.openedRoutes == [.history])
    #expect(recorder.resumeCount == 1)
}

@Test @MainActor func finishTestLaterCannotCompleteWhileTheTestRequestIsStillBeingPrepared() async {
    let pendingStore = SuspendedOnboardingPendingStore()
    let queue = LinkRequestQueue(store: pendingStore)
    let outcomes = LinkRoutingOutcomeCenter()
    let coordinator = RefusingExplicitOnboardingCoordinator()
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: BootstrapLinkBuffer(),
        sourceAttributor: OnboardingRoutingSourceAttributor(),
        lastActivatedSource: { nil },
        coordinator: coordinator
    )
    intake.finishRestorationAndStartDraining(routeAfterDraining: false)
    await intake.waitForPersistenceForTesting()
    let settings = OnboardingRoutingSettingsRepository(settings: .defaults, saveFails: false)
    let environment = makeOnboardingRoutingEnvironment(settings: settings)
    let recorder = OnboardingModelRecorder()
    let model = OnboardingViewModel(
        environment: environment,
        defaultBrowserService: DefaultBrowserService(
            client: ActiveOnboardingDefaultHandlerClient(),
            applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
            bundleIdentifier: "com.prism.app"
        ),
        browserCatalog: OnboardingRoutingCatalog(),
        testLinkRouter: OnboardingTestLinkRouter(
            intake: intake,
            coordinator: coordinator,
            outcomes: outcomes
        ),
        openMainWindow: { [recorder] route in recorder.openedRoutes.append(route) },
        resumeRouting: { [recorder] in recorder.resumeCount += 1 }
    )
    await model.advanceFromWelcome()
    await model.advanceFromLinkHandling()
    await model.advanceFromBrowserScan()
    await pendingStore.suspendNextSave()

    let begin = Task { @MainActor in await model.beginTestLink() }
    await pendingStore.waitUntilSaveSuspended()
    #expect(model.isTestLinkPreparing)
    await model.finishTestLater()

    #expect(model.isTestLinkInProgress)
    #expect(!environment.settings.onboardingCompleted)
    #expect(recorder.openedRoutes.isEmpty)
    #expect(recorder.resumeCount == 0)

    await pendingStore.releaseSuspendedSave()
    await begin.value
    #expect(!model.isTestLinkPreparing)
    #expect(!model.isTestLinkInProgress)
}

@Test @MainActor func explicitTestCaptureUsesTheAtomicQueueLaneWithoutStartingADrainWorker() async throws {
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    let bootstrap = BootstrapLinkBuffer()
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: bootstrap,
        sourceAttributor: OnboardingRoutingSourceAttributor(),
        lastActivatedSource: { nil }
    )
    intake.finishRestorationAndStartDraining(routeAfterDraining: false)
    await intake.waitForPersistenceForTesting()
    let workerCount = intake.workerStartCount

    let requestID = await intake.captureForExplicitSelection(
        url: onboardingRoutingURL,
        senderPID: nil
    )

    #expect(requestID != nil)
    #expect(bootstrap.snapshot().isEmpty)
    #expect(intake.workerStartCount == workerCount)
    #expect((await queue.snapshot()).map(\.id) == [requestID])
}

@Test @MainActor func explicitTestCaptureNeverOvertakesARealCaptureSuspendedInPersistence() async {
    let pendingStore = SuspendedOnboardingPendingStore()
    let queue = LinkRequestQueue(store: pendingStore)
    let bootstrap = BootstrapLinkBuffer()
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: bootstrap,
        sourceAttributor: OnboardingRoutingSourceAttributor(),
        lastActivatedSource: { nil }
    )
    intake.finishRestorationAndStartDraining(routeAfterDraining: false)
    await intake.waitForPersistenceForTesting()
    await pendingStore.suspendNextSave()

    #expect(intake.capture(
        url: URL(string: "https://older-real-request.example/private")!,
        senderPID: nil
    ))
    await pendingStore.waitUntilSaveSuspended()

    let testCapture = Task { @MainActor in
        await intake.captureForExplicitSelection(
            url: onboardingRoutingURL,
            senderPID: nil
        )
    }

    await pendingStore.releaseSuspendedSave()
    #expect(await testCapture.value == nil)
    await intake.waitForPersistenceForTesting()
    #expect((await queue.snapshot()).map(\.url.host) == ["older-real-request.example"])
}

@Test @MainActor func onboardingModelCompletesOnlyAfterItsRealHandoffAndResumesOnce() async throws {
    let fixture = OnboardingModelRoutingFixture(launchOutcomes: [.success])
    await fixture.enterTestLink()

    await fixture.model.beginTestLink()

    let request = try #require(fixture.routing.presenter.request)
    #expect(fixture.model.isTestLinkInProgress)
    #expect(!fixture.routing.environment.settings.onboardingCompleted)
    #expect(fixture.recorder.openedRoutes.isEmpty)
    #expect(fixture.recorder.resumeCount == 0)

    await fixture.routing.coordinator.select(
        browserID: onboardingRoutingBrowser.id,
        for: request.id
    )

    #expect(!fixture.model.isTestLinkInProgress)
    #expect(fixture.model.alert == nil)
    #expect(fixture.routing.environment.settings.onboardingCompleted)
    #expect(fixture.recorder.openedRoutes == [.history])
    #expect(fixture.recorder.resumeCount == 1)
}

@Test @MainActor func onboardingSaveFailureAfterAcceptedHandoffNeverResumesRouting() async throws {
    let fixture = OnboardingModelRoutingFixture(
        launchOutcomes: [.success]
    )
    await fixture.enterTestLink()
    fixture.routing.settingsRepository.saveFails = true
    await fixture.model.beginTestLink()
    let requestID = try #require(fixture.routing.presenter.request?.id)

    await fixture.routing.coordinator.select(
        browserID: onboardingRoutingBrowser.id,
        for: requestID
    )

    #expect(fixture.model.step == .testLink)
    #expect(fixture.model.alert == .settingsNotSaved)
    #expect(fixture.model.testLinkWasAccepted)
    #expect(!fixture.routing.environment.settings.onboardingCompleted)
    #expect(fixture.recorder.openedRoutes.isEmpty)
    #expect(fixture.recorder.resumeCount == 0)

    fixture.routing.settingsRepository.saveFails = false
    await fixture.model.retryCompletionSave()

    #expect(fixture.routing.launcher.openedURLs.count == 1)
    #expect(fixture.routing.environment.settings.onboardingCompleted)
    #expect(!fixture.model.testLinkWasAccepted)
    #expect(fixture.recorder.openedRoutes == [.history])
    #expect(fixture.recorder.resumeCount == 1)
}

@Test @MainActor func finishTestLaterCancelsObservationBeforeResumeAndIgnoresLateSuccess() async throws {
    let fixture = OnboardingModelRoutingFixture(launchOutcomes: [.success])
    await fixture.enterTestLink()
    await fixture.model.beginTestLink()
    let requestID = try #require(fixture.routing.presenter.request?.id)

    await fixture.model.finishTestLater()
    await fixture.routing.outcomes.report(LinkRoutingOutcome(
        requestID: requestID,
        kind: .handoffAccepted
    ))

    #expect(fixture.routing.environment.settings.onboardingCompleted)
    #expect(fixture.recorder.openedRoutes == [.history])
    #expect(fixture.recorder.resumeCount == 1)
}

@Test @MainActor func finishTestLaterDoesNotCompleteWhenCancellationCannotPersist() async throws {
    let pendingStore = FailingOnboardingPendingStore()
    let fixture = OnboardingModelRoutingFixture(
        launchOutcomes: [.success],
        pendingStore: pendingStore
    )
    await fixture.enterTestLink()
    await fixture.model.beginTestLink()
    let requestID = try #require(fixture.routing.presenter.request?.id)
    await pendingStore.failNextSave()

    await fixture.model.finishTestLater()

    #expect(fixture.model.alert == .testLinkCancellationFailed)
    #expect(fixture.model.isTestLinkInProgress)
    #expect(!fixture.routing.environment.settings.onboardingCompleted)
    #expect(fixture.recorder.openedRoutes.isEmpty)
    #expect(fixture.recorder.resumeCount == 0)
    #expect((await fixture.routing.queue.snapshot()).map(\.id) == [requestID])
    #expect((await fixture.routing.queue.snapshot()).map(\.state) == [.presenting])
    #expect(await fixture.routing.queue.terminalSnapshot().isEmpty)

    await fixture.model.beginTestLink()
    #expect((await fixture.routing.queue.snapshot()).map(\.id) == [requestID])

    await fixture.model.finishTestLater()

    #expect(fixture.routing.environment.settings.onboardingCompleted)
    #expect(!fixture.model.isTestLinkInProgress)
    #expect(fixture.recorder.openedRoutes == [.history])
    #expect(fixture.recorder.resumeCount == 1)
}

@Test @MainActor func finishTestLaterDoesNotCompleteWhileBrowserHandoffOwnsTheRequest() async throws {
    let fixture = OnboardingModelRoutingFixture(launchOutcomes: [.suspendedSuccess])
    await fixture.enterTestLink()
    await fixture.model.beginTestLink()
    let requestID = try #require(fixture.routing.presenter.request?.id)
    let selection = Task { @MainActor in
        await fixture.routing.coordinator.select(
            browserID: onboardingRoutingBrowser.id,
            for: requestID
        )
    }
    await fixture.routing.launcher.waitUntilHandoffIsSuspended()

    await fixture.model.finishTestLater()

    #expect(fixture.model.alert == .testLinkCancellationFailed)
    #expect(fixture.model.isTestLinkInProgress)
    #expect(!fixture.routing.environment.settings.onboardingCompleted)
    #expect(fixture.recorder.openedRoutes.isEmpty)
    #expect(fixture.recorder.resumeCount == 0)

    fixture.routing.launcher.acceptSuspendedHandoff()
    await selection.value

    #expect(fixture.routing.environment.settings.onboardingCompleted)
    #expect(!fixture.model.isTestLinkInProgress)
    #expect(fixture.recorder.openedRoutes == [.history])
    #expect(fixture.recorder.resumeCount == 1)
}

@Test @MainActor func onboardingModelKeepsOneTestRequestAcrossFailureAndRetry() async throws {
    let fixture = OnboardingModelRoutingFixture(launchOutcomes: [.failure, .success])
    await fixture.enterTestLink()

    await fixture.model.beginTestLink()
    await fixture.model.beginTestLink()

    let request = try #require(fixture.routing.presenter.request)
    #expect((await fixture.routing.queue.snapshot()).map(\.id) == [request.id])
    await fixture.routing.coordinator.select(
        browserID: onboardingRoutingBrowser.id,
        for: request.id
    )

    #expect(fixture.model.step == .testLink)
    #expect(fixture.model.isTestLinkInProgress)
    #expect(fixture.model.alert == .testLinkFailed)
    #expect(!fixture.routing.environment.settings.onboardingCompleted)
    #expect(fixture.recorder.resumeCount == 0)

    await fixture.routing.coordinator.retry(
        browserID: onboardingRoutingBrowser.id,
        for: request.id
    )

    #expect(fixture.routing.environment.settings.onboardingCompleted)
    #expect(fixture.recorder.resumeCount == 1)
}

@Test @MainActor func onboardingModelRejectsCancelAndMarkCompletedAsSuccess() async throws {
    let cancelled = OnboardingModelRoutingFixture(launchOutcomes: [.success])
    await cancelled.enterTestLink()
    await cancelled.model.beginTestLink()
    let cancelledRequest = try #require(cancelled.routing.presenter.request)
    await cancelled.routing.coordinator.cancel(requestID: cancelledRequest.id)

    #expect(!cancelled.model.isTestLinkInProgress)
    #expect(cancelled.model.alert == .testLinkFailed)
    #expect(!cancelled.routing.environment.settings.onboardingCompleted)
    #expect(cancelled.recorder.resumeCount == 0)

    let marked = OnboardingModelRoutingFixture(launchOutcomes: [.success])
    await marked.enterTestLink()
    await marked.model.beginTestLink()
    let markedRequest = try #require(marked.routing.presenter.request)
    await marked.routing.coordinator.markUncertainAttemptCompleted(requestID: markedRequest.id)

    #expect(!marked.model.isTestLinkInProgress)
    #expect(marked.model.alert == .testLinkFailed)
    #expect(!marked.routing.environment.settings.onboardingCompleted)
    #expect(marked.recorder.resumeCount == 0)
}

@MainActor
private struct OnboardingModelRoutingFixture {
    let routing: OnboardingRoutingFixture
    let recorder = OnboardingModelRecorder()
    let model: OnboardingViewModel

    init(
        launchOutcomes: [OnboardingRoutingLaunchOutcome],
        settingsSaveFails: Bool = false,
        pendingStore: any PendingRequestStore = InMemoryPendingRequestStore()
    ) {
        routing = OnboardingRoutingFixture(
            launchOutcomes: launchOutcomes,
            settingsSaveFails: settingsSaveFails,
            pendingStore: pendingStore
        )
        model = OnboardingViewModel(
            environment: routing.environment,
            defaultBrowserService: DefaultBrowserService(
                client: ActiveOnboardingDefaultHandlerClient(),
                applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
                bundleIdentifier: "com.prism.app"
            ),
            browserCatalog: routing.catalog,
            testLinkRouter: routing.router,
            openMainWindow: { [recorder] route in recorder.openedRoutes.append(route) },
            resumeRouting: { [recorder] in recorder.resumeCount += 1 }
        )
    }

    func enterTestLink() async {
        await model.advanceFromWelcome()
        await model.advanceFromLinkHandling()
        await model.advanceFromBrowserScan()
    }
}

@MainActor
private final class OnboardingModelRecorder {
    var openedRoutes: [AppRoute] = []
    var resumeCount = 0
}

@MainActor
private final class ActiveOnboardingDefaultHandlerClient: DefaultHandlerClient {
    func handlerBundleIdentifier(forScheme _: String) -> String? { "com.prism.app" }
    func setDefault(applicationURL _: URL, forScheme _: String) async throws {}
}

@MainActor
private final class ReentrantAcceptedOnboardingCoordinator: LinkRoutingCoordinating {
    private let queue: LinkRequestQueue
    private let outcomes: LinkRoutingOutcomeCenter
    private(set) var presentedRequestIDs: [UUID] = []
    weak var continuationRequester: (any LinkRoutingContinuationRequesting)?

    init(queue: LinkRequestQueue, outcomes: LinkRoutingOutcomeCenter) {
        self.queue = queue
        self.outcomes = outcomes
    }

    func processNext(
        while _: @escaping @MainActor () -> Bool
    ) async -> LinkRoutingPassDisposition {
        .drained
    }

    func presentForExplicitSelection(requestID: UUID) async -> Bool {
        presentedRequestIDs.append(requestID)
        try? await queue.markCompleted(requestID, historyEntry: nil)
        try? await queue.compactTerminal(requestID)
        await outcomes.report(LinkRoutingOutcome(
            requestID: requestID,
            kind: .handoffAccepted
        ))
        return true
    }

    func select(browserID _: BrowserID, for _: UUID) async {}
    func retry(browserID _: BrowserID, for _: UUID) async {}
    func markUncertainAttemptCompleted(requestID _: UUID) async {}
    func cancel(requestID _: UUID) async {}
}

@MainActor
private final class RefusingExplicitOnboardingCoordinator: LinkRoutingCoordinating {
    func processNext(
        while _: @escaping @MainActor () -> Bool
    ) async -> LinkRoutingPassDisposition {
        .drained
    }

    func presentForExplicitSelection(requestID _: UUID) async -> Bool { false }
    func select(browserID _: BrowserID, for _: UUID) async {}
    func retry(browserID _: BrowserID, for _: UUID) async {}
    func markUncertainAttemptCompleted(requestID _: UUID) async {}
    func cancel(requestID _: UUID) async {}
}

private actor SuspendedOnboardingPendingStore: PendingRequestStore {
    private var snapshot = PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])
    private var shouldSuspendNextSave = false
    private var suspendedSave: CheckedContinuation<Void, Never>?
    private var suspendedObservers: [CheckedContinuation<Void, Never>] = []

    func load() async throws -> PendingRequestSnapshot { snapshot }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        if shouldSuspendNextSave {
            shouldSuspendNextSave = false
            let observers = suspendedObservers
            suspendedObservers.removeAll()
            observers.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                suspendedSave = continuation
            }
        }
        self.snapshot = snapshot
    }

    func suspendNextSave() {
        shouldSuspendNextSave = true
    }

    func waitUntilSaveSuspended() async {
        if suspendedSave != nil { return }
        await withCheckedContinuation { continuation in
            suspendedObservers.append(continuation)
        }
    }

    func releaseSuspendedSave() {
        let continuation = suspendedSave
        suspendedSave = nil
        continuation?.resume()
    }
}

private actor FailingOnboardingPendingStore: PendingRequestStore {
    enum StoreError: Error {
        case saveFailed
    }

    private var snapshot = PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])
    private var shouldFailNextSave = false

    func load() async throws -> PendingRequestSnapshot { snapshot }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw StoreError.saveFailed
        }
        self.snapshot = snapshot
    }

    func failNextSave() {
        shouldFailNextSave = true
    }
}

@MainActor
private struct OnboardingRoutingFixture {
    let queue: LinkRequestQueue
    let coordinator: LinkRoutingCoordinator
    let presenter: OnboardingRoutingPresenter
    let launcher: OnboardingRoutingLauncher
    let router: OnboardingTestLinkRouter
    let environment: AppEnvironment
    let catalog: OnboardingRoutingCatalog
    let outcomes: LinkRoutingOutcomeCenter
    let settingsRepository: OnboardingRoutingSettingsRepository

    init(
        launchOutcomes: [OnboardingRoutingLaunchOutcome],
        settingsSaveFails: Bool = false,
        pendingStore: any PendingRequestStore = InMemoryPendingRequestStore()
    ) {
        queue = LinkRequestQueue(store: pendingStore)
        presenter = OnboardingRoutingPresenter()
        launcher = OnboardingRoutingLauncher(outcomes: launchOutcomes)
        outcomes = LinkRoutingOutcomeCenter()
        settingsRepository = OnboardingRoutingSettingsRepository(
            settings: .defaults,
            saveFails: settingsSaveFails
        )
        catalog = OnboardingRoutingCatalog()
        environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: InMemoryRuleRepository(),
            historyRepository: InMemoryHistoryRepository(),
            browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
            settingsRepository: settingsRepository
        )
        coordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: environment.ruleRepository,
            historyRepository: environment.historyRepository,
            settingsRepository: settingsRepository,
            browserCatalog: catalog,
            browserLauncher: launcher,
            sourceManifest: .disabled,
            presenter: presenter,
            warningPresenter: environment,
            outcomeReporter: outcomes
        )
        let intake = LinkIntakeService(
            queue: queue,
            bootstrap: BootstrapLinkBuffer(),
            sourceAttributor: OnboardingRoutingSourceAttributor(),
            lastActivatedSource: { nil },
            coordinator: coordinator
        )
        coordinator.continuationRequester = intake
        intake.finishRestorationAndStartDraining(routeAfterDraining: false)
        router = OnboardingTestLinkRouter(
            intake: intake,
            coordinator: coordinator,
            outcomes: outcomes
        )
    }
}

@MainActor
private final class OnboardingRoutingPresenter: LinkSelectionPresenting {
    private(set) var request: LinkRequest?
    private(set) var context: SelectorPresentationContext?

    func present(_ request: LinkRequest, context: SelectorPresentationContext) {
        self.request = request
        self.context = context
    }

    func dismiss(requestID: UUID) {
        guard request?.id == requestID else { return }
        request = nil
        context = nil
    }
}

private enum OnboardingRoutingLaunchOutcome {
    case success
    case failure
    case suspendedSuccess
}

@MainActor
private final class OnboardingRoutingLauncher: BrowserLaunching {
    private var outcomes: [OnboardingRoutingLaunchOutcome]
    private(set) var openedURLs: [URL] = []
    private var suspendedHandoff: CheckedContinuation<BrowserLaunchResult, Error>?
    private var suspensionObservers: [CheckedContinuation<Void, Never>] = []

    init(outcomes: [OnboardingRoutingLaunchOutcome]) {
        self.outcomes = outcomes
    }

    func open(_ url: URL, with _: BrowserDescriptor) async throws -> BrowserLaunchResult {
        openedURLs.append(url)
        let outcome = outcomes.isEmpty ? .success : outcomes.removeFirst()
        switch outcome {
        case .success:
            return .handoffSucceeded
        case .failure:
            throw OnboardingRoutingError.launchFailed
        case .suspendedSuccess:
            let observers = suspensionObservers
            suspensionObservers.removeAll()
            observers.forEach { $0.resume() }
            return try await withCheckedThrowingContinuation { continuation in
                suspendedHandoff = continuation
            }
        }
    }

    func waitUntilHandoffIsSuspended() async {
        if suspendedHandoff != nil { return }
        await withCheckedContinuation { continuation in
            suspensionObservers.append(continuation)
        }
    }

    func acceptSuspendedHandoff() {
        let continuation = suspendedHandoff
        suspendedHandoff = nil
        continuation?.resume(returning: .handoffSucceeded)
    }
}

@MainActor
private final class OnboardingRoutingCatalog: BrowserCataloging {
    func scan() async throws -> [BrowserDescriptor] { [onboardingRoutingBrowser] }
}

@MainActor
private struct OnboardingRoutingSourceAttributor: SourceAttributing {
    func resolve(senderPID _: Int32?, lastActivated _: SourceApplication?) -> SourceApplication {
        .unknown
    }
}

@MainActor
private final class OnboardingRoutingWarnings: PersistenceWarningPresenting {
    func present(_: PersistenceWarning) {}
}

private enum OnboardingRoutingError: Error {
    case launchFailed
    case settingsSaveFailed
}

@MainActor
private final class OnboardingRoutingSettingsRepository: SettingsRepository {
    private var settings: AppSettings
    var saveFails: Bool

    init(settings: AppSettings, saveFails: Bool) {
        self.settings = settings
        self.saveFails = saveFails
    }

    func load() throws -> AppSettings { settings }

    func save(_ settings: AppSettings) throws {
        if saveFails { throw OnboardingRoutingError.settingsSaveFailed }
        self.settings = settings
    }
}

@MainActor
private func makeOnboardingRoutingEnvironment(
    settings: any SettingsRepository
) -> AppEnvironment {
    AppEnvironment(
        route: .history,
        unmatchedBehavior: .alwaysAsk,
        updateChecker: DisabledUpdateChecker(),
        ruleRepository: InMemoryRuleRepository(),
        historyRepository: InMemoryHistoryRepository(),
        browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
        settingsRepository: settings
    )
}

private let onboardingRoutingURL = URL(string: "https://example.com/prism-onboarding-test")!
private let onboardingRoutingBrowser = BrowserDescriptor(
    id: "com.example.onboarding-browser",
    bundleIdentifier: "com.example.onboarding-browser",
    displayName: "Onboarding Browser",
    applicationURL: URL(fileURLWithPath: "/Applications/Onboarding Browser.app"),
    securityScopedBookmark: nil,
    origin: .system,
    availability: .available,
    selectorOrder: 0
)
