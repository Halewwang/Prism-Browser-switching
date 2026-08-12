import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func receivingTwoURLsEnqueuesTwoDifferentRequests() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: buffer,
        sourceAttributor: StubSourceAttributor(result: .unknown),
        lastActivatedSource: { nil }
    )

    #expect(intake.capture(url: URL(string: "https://one.example")!, senderPID: nil))
    #expect(intake.capture(url: URL(string: "https://two.example")!, senderPID: nil))
    try await intake.drainForTesting()

    let requests = await queue.snapshot()
    #expect(requests.map(\.url.host) == ["one.example", "two.example"])
    #expect(Set(requests.map(\.id)).count == 2)
}

@Test @MainActor func intakeNeverDropsACaptureWhenAQueuedIDAlreadyExists() async throws {
    let duplicateID = fixedUUID(1)
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    try await queue.enqueue(LinkRequest.fixture(id: duplicateID, url: "https://existing.example"))
    let buffer = BootstrapLinkBuffer(makeID: { duplicateID })
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: buffer,
        sourceAttributor: StubSourceAttributor(result: .unknown),
        lastActivatedSource: { nil }
    )
    intake.capture(url: URL(string: "https://captured.example/private?token=secret")!, senderPID: nil)

    await #expect(throws: Error.self) {
        try await intake.drainForTesting()
    }

    #expect(buffer.snapshot().map(\.url.host) == ["captured.example"])
    #expect(await queue.snapshot().map(\.url.host) == ["existing.example"])
}

@Test @MainActor func invalidSchemesNeverEnterBootstrapOrRecoveryStorage() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: buffer,
        sourceAttributor: StubSourceAttributor(result: .unknown),
        lastActivatedSource: { nil }
    )

    #expect(!intake.capture(url: URL(string: "file:///private/secret.txt")!, senderPID: 91))
    #expect(!intake.capture(url: URL(string: "prism://token/private")!, senderPID: 91))
    try await intake.drainForTesting()

    #expect(buffer.snapshot().isEmpty)
    #expect(await queue.snapshot().isEmpty)
}

@Test @MainActor func captureAssignsMonotonicSequenceAndCopiesPIDIntoAttribution() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer(now: { Date(timeIntervalSince1970: 10) })
    let attributor = StubSourceAttributor(result: SourceApplication(
        bundleIdentifier: "com.example.source",
        displayName: "Source",
        confidence: .confirmed
    ))
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: buffer,
        sourceAttributor: attributor,
        lastActivatedSource: { nil }
    )

    #expect(intake.capture(url: URL(string: "https://one.example")!, senderPID: 42))
    #expect(intake.capture(url: URL(string: "https://two.example")!, senderPID: 43))
    #expect(buffer.snapshot().map(\.sequence) == [0, 1])
    try await intake.drainForTesting()

    #expect(attributor.senderPIDs == [42, 43])
    #expect((await queue.snapshot()).map(\.receivedAt) == [
        Date(timeIntervalSince1970: 10),
        Date(timeIntervalSince1970: 10)
    ])
}

@Test @MainActor func coldStartBufferDrainsAfterRestoredRequests() async throws {
    let old = LinkRequest.fixture(url: "https://old.example")
    let store = ScriptedPendingRequestStore(snapshot: .init(pendingRequests: [old], terminalRecords: []))
    let queue = LinkRequestQueue(store: store)
    let bootstrap = BootstrapLinkBuffer()
    bootstrap.capture(URL(string: "https://new.example")!, senderPID: nil)
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: bootstrap,
        sourceAttributor: StubSourceAttributor(result: .unknown),
        lastActivatedSource: { nil }
    )

    try await queue.restore()
    try await intake.drainForTesting()

    #expect(await queue.snapshot().map(\.url.host) == ["old.example", "new.example"])
}

@Test @MainActor func failedEnqueueRetainsCapturedLinkForPersistenceOnlyRetry() async throws {
    let store = ScriptedPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let bootstrap = BootstrapLinkBuffer()
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: bootstrap,
        sourceAttributor: StubSourceAttributor(result: .unknown),
        lastActivatedSource: { nil }
    )
    intake.capture(url: URL(string: "https://kept.example/private?token=secret")!, senderPID: nil)
    await store.failNextSave()

    await #expect(throws: Error.self) {
        try await intake.drainForTesting()
    }
    #expect(bootstrap.snapshot().count == 1)
    #expect(await queue.snapshot().isEmpty)

    try await intake.drainForTesting()
    #expect(bootstrap.snapshot().isEmpty)
    #expect(await queue.snapshot().map(\.url.host) == ["kept.example"])
}

@Test @MainActor func oneWorkerRetriesPersistenceExplicitlyWithoutDuplicatingCapture() async throws {
    let store = ScriptedPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let bootstrap = BootstrapLinkBuffer()
    let coordinator = SpyRoutingCoordinator()
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: bootstrap,
        sourceAttributor: StubSourceAttributor(result: .unknown),
        lastActivatedSource: { nil },
        coordinator: coordinator
    )
    intake.capture(url: URL(string: "https://once.example")!, senderPID: nil)
    await store.failNextSave()

    intake.finishRestorationAndStartDraining()
    await intake.waitForDrainForTesting()
    #expect(bootstrap.snapshot().count == 1)
    #expect(await queue.snapshot().isEmpty)

    intake.retryPendingPersistenceAfterUserAction()
    await intake.waitForDrainForTesting()

    #expect(bootstrap.snapshot().isEmpty)
    #expect(await queue.snapshot().map(\.url.host) == ["once.example"])
    #expect(intake.workerStartCount == 2)
    #expect(coordinator.processNextCount == 0)

    await intake.resumeRoutingAfterRecoveryUserAction()

    #expect(coordinator.processNextCount == 1)
    #expect(intake.workerStartCount == 2)
}

@Test @MainActor func routingResumeRefusesToPersistABufferedCapture() async throws {
    let store = ScriptedPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let bootstrap = BootstrapLinkBuffer()
    let coordinator = SpyRoutingCoordinator()
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: bootstrap,
        sourceAttributor: StubSourceAttributor(result: .unknown),
        lastActivatedSource: { nil },
        coordinator: coordinator
    )
    intake.capture(url: URL(string: "https://still-buffered.example")!, senderPID: nil)
    await store.failNextSave()
    intake.finishRestorationAndStartDraining(routeAfterDraining: false)
    await intake.waitForDrainForTesting()

    intake.capture(url: URL(string: "https://also-buffered.example")!, senderPID: nil)
    await intake.waitForDrainForTesting()

    #expect(bootstrap.snapshot().map(\.url.host) == [
        "still-buffered.example",
        "also-buffered.example"
    ])
    #expect(await queue.snapshot().isEmpty)
    #expect(coordinator.processNextCount == 0)
    #expect(intake.workerStartCount == 1)

    await intake.resumeRoutingAfterRecoveryUserAction()
    await intake.waitForDrainForTesting()

    #expect(bootstrap.snapshot().map(\.url.host) == [
        "still-buffered.example",
        "also-buffered.example"
    ])
    #expect(await queue.snapshot().isEmpty)
    #expect(coordinator.processNextCount == 0)
    #expect(intake.workerStartCount == 1)

    intake.retryPendingPersistenceAfterUserAction()
    await intake.waitForDrainForTesting()

    #expect(bootstrap.snapshot().isEmpty)
    #expect(await queue.snapshot().map(\.url.host) == [
        "still-buffered.example",
        "also-buffered.example"
    ])
    #expect(coordinator.processNextCount == 0)
    #expect(intake.workerStartCount == 2)

    await intake.resumeRoutingAfterRecoveryUserAction()

    #expect(coordinator.processNextCount == 1)
    #expect(intake.workerStartCount == 2)
}

@Test @MainActor func tenRapidLinksRemainDistinctAndFIFO() async throws {
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    let intake = LinkIntakeService(
        queue: queue,
        bootstrap: BootstrapLinkBuffer(),
        sourceAttributor: StubSourceAttributor(result: .unknown),
        lastActivatedSource: { nil }
    )

    for value in 0..<10 {
        #expect(intake.capture(url: URL(string: "https://example.com/\(value)")!, senderPID: nil))
    }
    try await intake.drainForTesting()

    let requests = await queue.snapshot()
    #expect(requests.map(\.url.path) == (0..<10).map { "/\($0)" })
    #expect(Set(requests.map(\.id)).count == 10)
}

@Test @MainActor func automaticLaunchFailureKeepsTheSameRequestRecoverable() async throws {
    let harness = RoutingHarness(automaticBrowserID: "com.apple.Safari", launchResults: [.failure])
    let request = LinkRequest.fixture(id: fixedUUID(40), url: "https://example.com/fail")
    try await harness.queue.enqueue(request)

    await harness.coordinator.processNext()

    #expect(await harness.queue.next()?.id == request.id)
    #expect(harness.presenter.request?.id == request.id)
    #expect(harness.presenter.context == .launchFailed(
        browserID: "com.apple.Safari",
        message: "launch_failed"
    ))
    #expect(harness.history.entries.filter { $0.requestID == request.id }.count == 1)
    #expect(harness.history.entries[0].id == request.id)
    #expect(harness.history.entries[0].result == .failure)
    #expect(harness.launcher.handoffCount == 1)
}

@Test @MainActor func historyWriteFailureNeverReplaysSuccessfulHandoff() async throws {
    let harness = RoutingHarness(
        automaticBrowserID: "com.apple.Safari",
        launchResults: [.success],
        historyFailures: .always
    )
    let request = LinkRequest.fixture(id: fixedUUID(41), url: "https://example.com/private?token=secret")
    try await harness.queue.enqueue(request)

    await harness.coordinator.processNext()
    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 1)
    #expect(await harness.queue.next() == nil)
    #expect(await harness.queue.terminalSnapshot().first?.outcome == .succeeded)
    #expect(await harness.queue.terminalSnapshot().first?.historyEntry?.sanitizedURL?.absoluteString == "https://example.com/private")
    #expect(harness.warning.last == .historyNotSaved)
}

@Test @MainActor func launchingSaveFailureNeverCallsBrowser() async throws {
    let harness = RoutingHarness(automaticBrowserID: "com.apple.Safari", launchResults: [.success])
    let request = LinkRequest.fixture(id: fixedUUID(42))
    try await harness.queue.enqueue(request)
    await harness.pendingStore.failNextSave()

    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 0)
    #expect(harness.presenter.context == .storageUnavailable)
    #expect(await harness.queue.next()?.id == request.id)
}

@Test @MainActor func terminalSaveFailureAfterHandoffNeverHandsOffAgain() async throws {
    let harness = RoutingHarness(automaticBrowserID: "com.apple.Safari", launchResults: [.success, .success])
    let request = LinkRequest.fixture(id: fixedUUID(43))
    try await harness.queue.enqueue(request)
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 1)

    await harness.coordinator.processNext()
    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 1)
    #expect(harness.presenter.context == .outcomeUnknown(browserID: "com.apple.Safari"))
    #expect(harness.warning.last == .recoveryStoreUnavailable)
    #expect((await harness.queue.snapshot()).first?.state == .launching)
}

@Test @MainActor func uncertainRetryPersistenceFailureStillNeverHandsOffAgain() async throws {
    let harness = RoutingHarness(
        automaticBrowserID: "com.apple.Safari",
        launchResults: [.success, .success]
    )
    let request = LinkRequest.fixture(id: fixedUUID(431))
    try await harness.queue.enqueue(request)
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 1)
    await harness.coordinator.processNext()
    await harness.pendingStore.failNextSave()

    await harness.coordinator.retry(browserID: "com.apple.Safari", for: request.id)

    #expect(harness.launcher.handoffCount == 1)
    #expect((await harness.queue.snapshot()).first?.state == .launching)
    #expect(harness.presenter.context == .outcomeUnknown(browserID: "com.apple.Safari"))
    #expect(harness.warning.last == .recoveryStoreUnavailable)
}

@Test @MainActor func cancelWhileHandoffCompletionIsPendingCannotCreateAFalseCancelledOutcome() async throws {
    let store = ScriptedPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let presenter = SpySelectionPresenter()
    let launcher = SuspendedBrowserLauncher()
    let history = StubHistoryRepository()
    var settingsValue = AppSettings.defaults
    settingsValue.unmatchedBehavior = .preferredBrowser
    settingsValue.preferredBrowserID = "com.apple.Safari"
    let settings = StubSettingsRepository(settings: settingsValue)
    let coordinator = LinkRoutingCoordinator(
        queue: queue,
        ruleRepository: StubRuleRepository(),
        historyRepository: history,
        settingsRepository: settings,
        browserCatalog: StubBrowserCatalog(browsers: [testSafariDescriptor]),
        browserLauncher: launcher,
        sourceManifest: .disabled,
        presenter: presenter,
        warningPresenter: SpyWarningPresenter()
    )
    let request = LinkRequest.fixture(id: fixedUUID(430))
    try await queue.enqueue(request)

    let processing = Task { @MainActor in
        await coordinator.processNext()
    }
    await launcher.waitUntilStarted()
    await coordinator.cancel(requestID: request.id)

    #expect((await queue.snapshot()).first?.state == .launching)
    #expect(history.entries.first?.result == .processing)

    launcher.succeed()
    await processing.value

    #expect(launcher.handoffCount == 1)
    #expect(await queue.next() == nil)
    #expect(history.entries.count == 1)
    #expect(history.entries.first?.result == .success)
    #expect(presenter.context != .outcomeUnknown(browserID: "com.apple.Safari"))
}

@Test @MainActor func failedHandoffPresentationSaveFailureStopsDrainWithoutRelaunch() async throws {
    let harness = RoutingHarness(automaticBrowserID: "com.apple.Safari", launchResults: [.failure, .success])
    let request = LinkRequest.fixture(id: fixedUUID(44))
    try await harness.queue.enqueue(request)
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 1)

    await harness.coordinator.processNext()
    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 1)
    #expect(harness.presenter.request?.id == request.id)
    #expect(harness.presenter.context == .storageUnavailable)
    #expect((await harness.queue.snapshot()).first?.state == .launching)
}

@Test @MainActor func failedHandoffStorageRetryRepairsPersistenceWithoutOpeningAgain() async throws {
    let harness = RoutingHarness(automaticBrowserID: "com.apple.Safari", launchResults: [.failure, .success])
    let request = LinkRequest.fixture(id: fixedUUID(440))
    try await harness.queue.enqueue(request)
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 1)
    await harness.coordinator.processNext()

    await harness.coordinator.retry(browserID: "com.apple.Safari", for: request.id)

    #expect(harness.launcher.handoffCount == 1)
    #expect((await harness.queue.snapshot()).first?.state == .presenting)
    #expect(harness.presenter.context == .launchFailed(
        browserID: "com.apple.Safari",
        message: "launch_failed"
    ))
}

@Test @MainActor func terminalCompactionFailureLeavesURLFreeRecordAndDoesNotReplay() async throws {
    let harness = RoutingHarness(automaticBrowserID: "com.apple.Safari", launchResults: [.success])
    let request = LinkRequest.fixture(id: fixedUUID(45), url: "https://example.com/private?token=secret")
    try await harness.queue.enqueue(request)
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 2)

    await harness.coordinator.processNext()
    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 1)
    #expect(await harness.queue.snapshot().isEmpty)
    let terminal = try #require(await harness.queue.terminalSnapshot().first)
    #expect(terminal.requestID == request.id)
    #expect(terminal.historyEntry?.sanitizedURL?.absoluteString == "https://example.com/private")
    #expect(harness.warning.last == .recoveryStoreUnavailable)
}

@Test @MainActor func restoredInterruptedLaunchPresentsOutcomeUnknownWithoutOpeningBrowser() async throws {
    let request = LinkRequest.fixture(
        id: fixedUUID(46),
        state: .launching
    )
    let harness = RoutingHarness(
        launchResults: [.success],
        restoredSnapshot: .init(pendingRequests: [request], terminalRecords: [])
    )
    try await harness.queue.restore()

    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 0)
    #expect(harness.presenter.request?.id == request.id)
    #expect(harness.presenter.context == .outcomeUnknown(browserID: nil))
    #expect((await harness.queue.snapshot()).first?.state == .outcomeUnknown)
}

@Test @MainActor func explicitRetryUsesSameRequestAndStartsANewAttempt() async throws {
    let request = LinkRequest(
        id: fixedUUID(47),
        url: URL(string: "https://example.com")!,
        receivedAt: .now,
        source: .unknown,
        state: .outcomeUnknown,
        attemptCount: 1,
        lastAttemptedBrowserID: "com.apple.Safari"
    )
    let harness = RoutingHarness(
        launchResults: [.success],
        restoredSnapshot: .init(pendingRequests: [request], terminalRecords: [])
    )
    try await harness.queue.restore()
    await harness.coordinator.processNext()

    await harness.coordinator.retry(browserID: "com.apple.Safari", for: request.id)

    #expect(harness.launcher.handoffCount == 1)
    #expect(await harness.queue.next() == nil)
    #expect(harness.history.entries.first?.requestID == request.id)
    #expect(harness.history.entries.first?.attemptCount == 2)
}

@Test @MainActor func markCompletedResolvesUnknownOutcomeWithoutAnotherHandoff() async throws {
    let request = LinkRequest(
        id: fixedUUID(48),
        url: URL(string: "https://example.com")!,
        receivedAt: .now,
        source: .unknown,
        state: .outcomeUnknown,
        attemptCount: 1,
        lastAttemptedBrowserID: "com.apple.Safari"
    )
    let harness = RoutingHarness(
        launchResults: [.success],
        restoredSnapshot: .init(pendingRequests: [request], terminalRecords: [])
    )
    try await harness.queue.restore()

    await harness.coordinator.markUncertainAttemptCompleted(requestID: request.id)

    #expect(harness.launcher.handoffCount == 0)
    #expect(await harness.queue.next() == nil)
    #expect(harness.history.entries.first?.result == .success)
    #expect(harness.history.entries.first?.attemptCount == 1)
}

@Test @MainActor func markCompletedStorageFailureKeepsUnknownRequestWithoutHandoffOrHistoryWrite() async throws {
    let request = LinkRequest(
        id: fixedUUID(480),
        url: URL(string: "https://example.com/private?token=secret")!,
        receivedAt: .now,
        source: .unknown,
        state: .outcomeUnknown,
        attemptCount: 1,
        lastAttemptedBrowserID: "com.apple.Safari"
    )
    let harness = RoutingHarness(
        launchResults: [.success],
        restoredSnapshot: .init(pendingRequests: [request], terminalRecords: [])
    )
    try await harness.queue.restore()
    await harness.pendingStore.failNextSave()

    await harness.coordinator.markUncertainAttemptCompleted(requestID: request.id)

    #expect(await harness.queue.next()?.id == request.id)
    #expect((await harness.queue.snapshot()).first?.state == .outcomeUnknown)
    #expect(harness.launcher.handoffCount == 0)
    #expect(harness.history.entries.isEmpty)
    #expect(harness.presenter.context == .outcomeUnknown(browserID: "com.apple.Safari"))
    #expect(harness.warning.last == .recoveryStoreUnavailable)
}

@Test @MainActor func cancellationIsAtomicAndStoresOnlySanitizedHistory() async throws {
    let harness = RoutingHarness()
    let request = LinkRequest.fixture(
        id: fixedUUID(49),
        url: "https://example.com/private?token=secret&safe=kept#fragment"
    )
    try await harness.queue.enqueue(request)

    await harness.coordinator.cancel(requestID: request.id)

    #expect(await harness.queue.next() == nil)
    #expect(harness.launcher.handoffCount == 0)
    #expect(harness.history.entries.count == 1)
    #expect(harness.history.entries[0].result == .cancelled)
    #expect(harness.history.entries[0].sanitizedURL?.absoluteString == "https://example.com/private?safe=kept")
}

@Test @MainActor func cancellationStoreFailureKeepsRequestAndShowsStorageError() async throws {
    let harness = RoutingHarness()
    let request = LinkRequest.fixture(id: fixedUUID(50))
    try await harness.queue.enqueue(request)
    await harness.pendingStore.failNextSave()

    await harness.coordinator.cancel(requestID: request.id)

    #expect(await harness.queue.next()?.id == request.id)
    #expect(harness.history.entries.isEmpty)
    #expect(harness.presenter.context == .storageUnavailable)
}

@Test @MainActor func noAvailableBrowsersKeepsRequestPendingAndPresentsRecovery() async throws {
    let harness = RoutingHarness(browsers: [])
    let request = LinkRequest.fixture(id: fixedUUID(51))
    try await harness.queue.enqueue(request)

    await harness.coordinator.processNext()

    #expect(await harness.queue.next()?.id == request.id)
    #expect(harness.presenter.context == .noAvailableBrowsers)
    #expect(harness.launcher.handoffCount == 0)
}

@Test @MainActor func browserCatalogStorageFailureShowsStorageRecoveryWithoutLaunching() async throws {
    let harness = RoutingHarness(launchResults: [.success])
    harness.catalog.error = StubRoutingError.storageFailed
    let request = LinkRequest.fixture(id: fixedUUID(510))
    try await harness.queue.enqueue(request)

    await harness.coordinator.processNext()

    #expect(await harness.queue.next()?.id == request.id)
    #expect(harness.presenter.context == .storageUnavailable)
    #expect(harness.warning.last == .recoveryStoreUnavailable)
    #expect(harness.launcher.handoffCount == 0)
}

@Test @MainActor func manualSelectionCatalogFailureRemainsPendingWithStorageRecovery() async throws {
    let harness = RoutingHarness(launchResults: [.success])
    let request = LinkRequest.fixture(id: fixedUUID(511))
    try await harness.queue.enqueue(request)
    await harness.coordinator.processNext()
    harness.catalog.error = StubRoutingError.storageFailed

    await harness.coordinator.select(browserID: "com.apple.Safari", for: request.id)

    #expect(await harness.queue.next()?.id == request.id)
    #expect(harness.presenter.context == .storageUnavailable)
    #expect(harness.warning.last == .recoveryStoreUnavailable)
    #expect(harness.launcher.handoffCount == 0)
}

@Test @MainActor func historyDisabledBuildsAndPersistsNoHistoryEntry() async throws {
    var settings = AppSettings.defaults
    settings.unmatchedBehavior = .preferredBrowser
    settings.preferredBrowserID = "com.apple.Safari"
    settings.historyEnabled = false
    let harness = RoutingHarness(launchResults: [.success], settings: settings)
    let request = LinkRequest.fixture(id: fixedUUID(52))
    try await harness.queue.enqueue(request)

    await harness.coordinator.processNext()

    #expect(harness.history.upsertCallCount == 0)
    #expect(harness.history.entries.isEmpty)
    #expect(await harness.queue.terminalSnapshot().isEmpty)
    #expect(harness.launcher.handoffCount == 1)
}

@Test @MainActor func historyDisabledCancellationBuildsNoEntry() async throws {
    var settings = AppSettings.defaults
    settings.historyEnabled = false
    let harness = RoutingHarness(settings: settings)
    let request = LinkRequest.fixture(id: fixedUUID(520))
    try await harness.queue.enqueue(request)

    await harness.coordinator.cancel(requestID: request.id)

    #expect(harness.history.upsertCallCount == 0)
    #expect(harness.history.entries.isEmpty)
    #expect(await harness.queue.next() == nil)
    #expect(await harness.queue.terminalSnapshot().isEmpty)
}

@Test @MainActor func cancellationHistoryFailureNeverResurrectsRequest() async throws {
    let harness = RoutingHarness(historyFailures: .always)
    let request = LinkRequest.fixture(id: fixedUUID(521))
    try await harness.queue.enqueue(request)

    await harness.coordinator.cancel(requestID: request.id)
    await harness.coordinator.processNext()

    #expect(await harness.queue.next() == nil)
    #expect(await harness.queue.terminalSnapshot().first?.outcome == .cancelled)
    #expect(harness.warning.last == .historyNotSaved)
    #expect(harness.launcher.handoffCount == 0)
}

@Test @MainActor func manualSuccessSurvivesLastUsedPreferenceFailure() async throws {
    let settings = StubSettingsRepository(settings: .defaults, failSave: true)
    let harness = RoutingHarness(launchResults: [.success], settingsRepository: settings)
    let request = LinkRequest.fixture(id: fixedUUID(53))
    try await harness.queue.enqueue(request)
    await harness.coordinator.processNext()

    await harness.coordinator.select(browserID: "com.apple.Safari", for: request.id)

    #expect(harness.launcher.handoffCount == 1)
    #expect(await harness.queue.next() == nil)
    #expect(harness.history.entries.first?.result == .success)
    #expect(harness.warning.last == .settingsNotSaved)
}

@Test @MainActor func sourceRuleUsesManifestEligibilityInProductionCoordinator() async throws {
    let sourceID = "com.example.approved"
    let manifest = try SourceSupportManifest.decode(Data(#"{"schemaVersion":1,"sources":[{"bundleIdentifier":"com.example.approved","minimumMacOS":"15.0.0","maximumMacOS":"15.9.99","coldSamples":20,"warmSamples":20,"confirmedCount":40,"falseAttributionCount":0,"validatedAt":"2026-08-12T00:00:00Z"}]}"#.utf8))
    let rule = RoutingRule(
        id: fixedUUID(54),
        isEnabled: true,
        matcher: .sourceBundleIdentifier(sourceID),
        targetBrowserID: "com.apple.Safari",
        priority: 0,
        label: nil,
        createdAt: .now,
        updatedAt: .now
    )
    let rules = StubRuleRepository(rules: [rule])
    let harness = RoutingHarness(
        launchResults: [.success],
        rulesRepository: rules,
        sourceManifest: manifest,
        operatingSystemVersion: .init(majorVersion: 15, minorVersion: 2, patchVersion: 0)
    )
    let request = LinkRequest.fixture(
        id: fixedUUID(55),
        source: SourceApplication(bundleIdentifier: sourceID, displayName: "Approved", confidence: .confirmed)
    )
    try await harness.queue.enqueue(request)

    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 1)
    #expect(harness.history.entries.first?.method == .sourceRule)
}

@Test @MainActor func settingsLoadFailureUsesAlwaysAskAndNeverAutomaticallyLaunches() async throws {
    let settings = StubSettingsRepository(settings: .defaults, failLoad: true)
    let harness = RoutingHarness(launchResults: [.success], settingsRepository: settings)
    let request = LinkRequest.fixture(id: fixedUUID(56))
    try await harness.queue.enqueue(request)

    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 0)
    #expect(harness.presenter.context == .normal)
    #expect(harness.warning.last == .settingsNotSaved)
}

@Test @MainActor func settingsLoadFailureManualSelectionWritesNoHistoryOrPreference() async throws {
    let settings = StubSettingsRepository(settings: .defaults, failLoad: true)
    let harness = RoutingHarness(launchResults: [.success], settingsRepository: settings)
    let request = LinkRequest.fixture(
        id: fixedUUID(560),
        url: "https://example.com/private?token=secret"
    )
    try await harness.queue.enqueue(request)
    await harness.coordinator.processNext()
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 2)

    await harness.coordinator.select(browserID: "com.apple.Safari", for: request.id)

    #expect(harness.launcher.handoffCount == 1)
    #expect(harness.history.upsertCallCount == 0)
    #expect(settings.saveCount == 0)
    let terminal = try #require(await harness.queue.terminalSnapshot().first)
    #expect(terminal.outcome == .succeeded)
    #expect(terminal.historyEntry == nil)
    #expect(await harness.queue.next() == nil)
}

@Test @MainActor func settingsLoadFailureExplicitRetryWritesNoHistoryOrPreference() async throws {
    let request = LinkRequest(
        id: fixedUUID(561),
        url: URL(string: "https://example.com/private?token=secret")!,
        receivedAt: .now,
        source: .unknown,
        state: .outcomeUnknown,
        attemptCount: 1,
        lastAttemptedBrowserID: "com.apple.Safari"
    )
    let settings = StubSettingsRepository(settings: .defaults, failLoad: true)
    let harness = RoutingHarness(
        launchResults: [.success],
        settingsRepository: settings,
        restoredSnapshot: .init(pendingRequests: [request], terminalRecords: [])
    )
    try await harness.queue.restore()
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 2)

    await harness.coordinator.retry(browserID: "com.apple.Safari", for: request.id)

    #expect(harness.launcher.handoffCount == 1)
    #expect(harness.history.upsertCallCount == 0)
    #expect(settings.saveCount == 0)
    let terminal = try #require(await harness.queue.terminalSnapshot().first)
    #expect(terminal.outcome == .succeeded)
    #expect(terminal.historyEntry == nil)
    #expect(await harness.queue.next() == nil)
}

@Test @MainActor func settingsLoadFailureDuringFailedHandoffRetryAddsNoHistoryWrite() async throws {
    var initialSettings = AppSettings.defaults
    initialSettings.unmatchedBehavior = .preferredBrowser
    initialSettings.preferredBrowserID = "com.apple.Safari"
    let settings = StubSettingsRepository(settings: initialSettings)
    let harness = RoutingHarness(
        launchResults: [.failure],
        settingsRepository: settings
    )
    let request = LinkRequest.fixture(id: fixedUUID(5610))
    try await harness.queue.enqueue(request)
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 1)
    await harness.coordinator.processNext()
    let historyCallsBeforeRetry = harness.history.upsertCallCount
    settings.failLoad = true

    await harness.coordinator.retry(browserID: "com.apple.Safari", for: request.id)

    #expect(settings.loadCount == 2)
    #expect(harness.history.upsertCallCount == historyCallsBeforeRetry)
    #expect((await harness.queue.snapshot()).first?.state == .presenting)
    #expect(harness.launcher.handoffCount == 1)
    #expect(harness.warning.warnings.contains(.settingsNotSaved))
}

@Test @MainActor func settingsLoadFailureCancellationWritesNoHistory() async throws {
    let settings = StubSettingsRepository(settings: .defaults, failLoad: true)
    let harness = RoutingHarness(settingsRepository: settings)
    let request = LinkRequest.fixture(
        id: fixedUUID(562),
        url: "https://example.com/private?token=secret"
    )
    try await harness.queue.enqueue(request)
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 1)

    await harness.coordinator.cancel(requestID: request.id)

    #expect(harness.launcher.handoffCount == 0)
    #expect(harness.history.upsertCallCount == 0)
    #expect(settings.saveCount == 0)
    let terminal = try #require(await harness.queue.terminalSnapshot().first)
    #expect(terminal.outcome == .cancelled)
    #expect(terminal.historyEntry == nil)
    #expect(await harness.queue.next() == nil)
}

@Test @MainActor func settingsLoadFailureMarkCompletedWritesNoHistory() async throws {
    let request = LinkRequest(
        id: fixedUUID(563),
        url: URL(string: "https://example.com/private?token=secret")!,
        receivedAt: .now,
        source: .unknown,
        state: .outcomeUnknown,
        attemptCount: 1,
        lastAttemptedBrowserID: "com.apple.Safari"
    )
    let settings = StubSettingsRepository(settings: .defaults, failLoad: true)
    let harness = RoutingHarness(
        settingsRepository: settings,
        restoredSnapshot: .init(pendingRequests: [request], terminalRecords: [])
    )
    try await harness.queue.restore()
    await harness.pendingStore.failSave(afterAdditionalSuccessfulSaves: 1)

    await harness.coordinator.markUncertainAttemptCompleted(requestID: request.id)

    #expect(harness.launcher.handoffCount == 0)
    #expect(harness.history.upsertCallCount == 0)
    #expect(settings.saveCount == 0)
    let terminal = try #require(await harness.queue.terminalSnapshot().first)
    #expect(terminal.outcome == .succeeded)
    #expect(terminal.historyEntry == nil)
    #expect(await harness.queue.next() == nil)
}

@Test @MainActor func settingsLoadFailureReconcilesTerminalWithoutWritingHistory() async throws {
    let requestID = fixedUUID(564)
    let historyEntry = HistoryEntry(
        id: requestID,
        requestID: requestID,
        sanitizedURL: URL(string: "https://example.com/private")!,
        sourceBundleIdentifier: "com.example.source",
        sourceDisplayName: "Example",
        targetBrowserID: "com.apple.Safari",
        targetDisplayName: "Safari",
        method: .manual,
        result: .success,
        matchingRuleID: nil,
        failureReason: nil,
        attemptCount: 1,
        createdAt: Date(timeIntervalSince1970: 100),
        completedAt: Date(timeIntervalSince1970: 101)
    )
    let store = ScriptedPendingRequestStore(snapshot: .init(
        pendingRequests: [],
        terminalRecords: [TerminalRequestRecord(
            requestID: requestID,
            outcome: .succeeded,
            historyEntry: historyEntry,
            completedAt: Date(timeIntervalSince1970: 101)
        )]
    ))
    let queue = LinkRequestQueue(store: store)
    let history = StubHistoryRepository()
    let settings = StubSettingsRepository(settings: .defaults, failLoad: true)
    let environment = AppEnvironment(
        route: .history,
        unmatchedBehavior: .alwaysAsk,
        updateChecker: DisabledUpdateChecker(),
        ruleRepository: StubRuleRepository(),
        historyRepository: history,
        browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
        settingsRepository: settings
    )

    let restored = await environment.restoreAndReconcile(queue: queue, warningSource: nil)

    #expect(restored)
    #expect(history.upsertCallCount == 0)
    #expect(settings.saveCount == 0)
    let terminal = try #require(await queue.terminalSnapshot().first)
    #expect(terminal.requestID == requestID)
    #expect(terminal.outcome == .succeeded)
    #expect(terminal.historyEntry == nil)
    #expect(await queue.next() == nil)
    #expect(environment.persistenceWarnings == [.settingsNotSaved])
}

@MainActor
private struct RoutingHarness {
    let pendingStore: ScriptedPendingRequestStore
    let queue: LinkRequestQueue
    let presenter: SpySelectionPresenter
    let launcher: StubBrowserLauncher
    let history: StubHistoryRepository
    let settings: StubSettingsRepository
    let rules: StubRuleRepository
    let catalog: StubBrowserCatalog
    let warning: SpyWarningPresenter
    let coordinator: LinkRoutingCoordinator

    init(
        automaticBrowserID: BrowserID? = nil,
        browsers: [BrowserDescriptor]? = nil,
        launchResults: [StubBrowserLauncher.Result] = [],
        historyFailures: StubHistoryRepository.FailureMode = .never,
        settings: AppSettings? = nil,
        settingsRepository: StubSettingsRepository? = nil,
        rulesRepository: StubRuleRepository? = nil,
        sourceManifest: SourceSupportManifest = .disabled,
        operatingSystemVersion: OperatingSystemVersion = .init(majorVersion: 15, minorVersion: 0, patchVersion: 0),
        restoredSnapshot: PendingRequestSnapshot = .init(pendingRequests: [], terminalRecords: [])
    ) {
        pendingStore = ScriptedPendingRequestStore(snapshot: restoredSnapshot)
        queue = LinkRequestQueue(store: pendingStore)
        presenter = SpySelectionPresenter()
        launcher = StubBrowserLauncher(results: launchResults)
        history = StubHistoryRepository(failureMode: historyFailures)
        var resolvedSettings = settings ?? .defaults
        if let automaticBrowserID {
            resolvedSettings.unmatchedBehavior = .preferredBrowser
            resolvedSettings.preferredBrowserID = automaticBrowserID
        }
        self.settings = settingsRepository ?? StubSettingsRepository(settings: resolvedSettings)
        rules = rulesRepository ?? StubRuleRepository()
        catalog = StubBrowserCatalog(browsers: browsers ?? [Self.safari])
        warning = SpyWarningPresenter()
        coordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: rules,
            historyRepository: history,
            settingsRepository: self.settings,
            browserCatalog: catalog,
            browserLauncher: launcher,
            sourceManifest: sourceManifest,
            operatingSystemVersion: operatingSystemVersion,
            presenter: presenter,
            warningPresenter: warning
        )
    }

    private static let safari = BrowserDescriptor(
        id: "com.apple.Safari",
        bundleIdentifier: "com.apple.Safari",
        displayName: "Safari",
        applicationURL: URL(fileURLWithPath: "/Applications/Safari.app"),
        securityScopedBookmark: nil,
        origin: .system,
        availability: .available,
        selectorOrder: 0
    )
}

@MainActor
private final class StubSourceAttributor: SourceAttributing {
    let result: SourceApplication
    private(set) var senderPIDs: [Int32?] = []

    init(result: SourceApplication) {
        self.result = result
    }

    func resolve(senderPID: Int32?, lastActivated _: SourceApplication?) -> SourceApplication {
        senderPIDs.append(senderPID)
        return result
    }
}

@MainActor
private final class SpySelectionPresenter: LinkSelectionPresenting {
    private(set) var request: LinkRequest?
    private(set) var context: SelectorPresentationContext?
    private(set) var dismissals: [UUID] = []

    func present(_ request: LinkRequest, context: SelectorPresentationContext) {
        self.request = request
        self.context = context
    }

    func dismiss(requestID: UUID) {
        dismissals.append(requestID)
        if request?.id == requestID {
            request = nil
            context = nil
        }
    }
}

@MainActor
private final class SpyWarningPresenter: PersistenceWarningPresenting {
    private(set) var warnings: [PersistenceWarning] = []
    var last: PersistenceWarning? { warnings.last }

    func present(_ warning: PersistenceWarning) {
        warnings.append(warning)
    }
}

@MainActor
private final class SpyRoutingCoordinator: LinkRoutingCoordinating {
    private(set) var processNextCount = 0

    func processNext() async {
        processNextCount += 1
    }

    func select(browserID _: BrowserID, for _: UUID) async {}
    func retry(browserID _: BrowserID, for _: UUID) async {}
    func markUncertainAttemptCompleted(requestID _: UUID) async {}
    func cancel(requestID _: UUID) async {}
}

@MainActor
private final class StubBrowserCatalog: BrowserCataloging {
    var browsers: [BrowserDescriptor]
    var error: Error?

    init(browsers: [BrowserDescriptor]) {
        self.browsers = browsers
    }

    func scan() async throws -> [BrowserDescriptor] {
        if let error { throw error }
        return browsers
    }
}

@MainActor
private final class StubBrowserLauncher: BrowserLaunching {
    enum Result {
        case success
        case failure
    }

    private var results: [Result]
    private(set) var handoffCount = 0

    init(results: [Result]) {
        self.results = results
    }

    func open(_: URL, with _: BrowserDescriptor) async throws -> BrowserLaunchResult {
        handoffCount += 1
        let result = results.isEmpty ? .success : results.removeFirst()
        switch result {
        case .success:
            return .handoffSucceeded
        case .failure:
            throw StubRoutingError.launchFailed
        }
    }
}

@MainActor
private final class SuspendedBrowserLauncher: BrowserLaunching {
    private var continuation: CheckedContinuation<BrowserLaunchResult, Error>?
    private(set) var handoffCount = 0

    func open(_: URL, with _: BrowserDescriptor) async throws -> BrowserLaunchResult {
        handoffCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func succeed() {
        continuation?.resume(returning: .handoffSucceeded)
        continuation = nil
    }
}

@MainActor
private final class StubHistoryRepository: HistoryRepository {
    enum FailureMode {
        case never
        case always
    }

    private let failureMode: FailureMode
    private var values: [UUID: HistoryEntry] = [:]
    private(set) var upsertCallCount = 0
    var entries: [HistoryEntry] {
        values.values.sorted { $0.createdAt < $1.createdAt }
    }

    init(failureMode: FailureMode = .never) {
        self.failureMode = failureMode
    }

    func upsert(_ entry: HistoryEntry) throws {
        upsertCallCount += 1
        if failureMode == .always { throw StubRoutingError.storageFailed }
        values[entry.id] = entry
    }

    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry] {
        Array(entries.filter { $0.createdAt >= newerThan }.prefix(limit))
    }

    func delete(id: UUID) throws { values[id] = nil }
    func clear() throws { values.removeAll() }
    func enforceRetention(limit _: Int, cutoff _: Date) throws {}
}

@MainActor
private final class StubSettingsRepository: SettingsRepository {
    private(set) var settings: AppSettings
    var failLoad: Bool
    private let failSave: Bool
    private(set) var loadCount = 0
    private(set) var saveCount = 0

    init(settings: AppSettings, failLoad: Bool = false, failSave: Bool = false) {
        self.settings = settings
        self.failLoad = failLoad
        self.failSave = failSave
    }

    func load() throws -> AppSettings {
        loadCount += 1
        if failLoad { throw StubRoutingError.storageFailed }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        saveCount += 1
        if failSave { throw StubRoutingError.storageFailed }
        self.settings = settings
    }
}

@MainActor
private final class StubRuleRepository: RuleRepository {
    private var rules: [RoutingRule]

    init(rules: [RoutingRule] = []) {
        self.rules = rules
    }

    func all() throws -> [RoutingRule] { rules }
    func upsert(_ rule: RoutingRule) throws { rules.append(rule) }
    func delete(id: UUID) throws { rules.removeAll { $0.id == id } }
}

private actor ScriptedPendingRequestStore: PendingRequestStore {
    private var snapshot: PendingRequestSnapshot
    private var failingSaveCalls: Set<Int> = []
    private(set) var saveCount = 0

    init(snapshot: PendingRequestSnapshot = .init(pendingRequests: [], terminalRecords: [])) {
        self.snapshot = snapshot
    }

    func load() async throws -> PendingRequestSnapshot {
        snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        saveCount += 1
        if failingSaveCalls.remove(saveCount) != nil {
            throw StubRoutingError.storageFailed
        }
        self.snapshot = snapshot
    }

    func failNextSave() {
        failingSaveCalls.insert(saveCount + 1)
    }

    func failSave(afterAdditionalSuccessfulSaves count: Int) {
        failingSaveCalls.insert(saveCount + count + 1)
    }
}

private enum StubRoutingError: Error {
    case launchFailed
    case storageFailed
}

private let testSafariDescriptor = BrowserDescriptor(
    id: "com.apple.Safari",
    bundleIdentifier: "com.apple.Safari",
    displayName: "Safari",
    applicationURL: URL(fileURLWithPath: "/Applications/Safari.app"),
    securityScopedBookmark: nil,
    origin: .system,
    availability: .available,
    selectorOrder: 0
)

private func fixedUUID(_ value: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
}
