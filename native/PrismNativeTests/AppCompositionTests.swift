import AppKit
import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func productionCompositionFallsBackToSafeEnvironmentWhenPersistenceCannotStart() async {
    let modelFailure = ProductionAppComposition.makeForTesting(
        modelContainerFactory: { throw TestCompositionFailure.unavailable },
        recoveryStoreFactory: { throw TestCompositionFailure.unavailable }
    )

    #expect(modelFailure.environment.unmatchedBehavior == .alwaysAsk)
    #expect(modelFailure.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))

    let recoveryFailure = ProductionAppComposition.makeForTesting(
        modelContainerFactory: { try ModelContainerFactory.make(inMemory: true) },
        recoveryStoreFactory: { throw TestCompositionFailure.unavailable }
    )
    await recoveryFailure.finishLaunchingOnce()

    #expect(recoveryFailure.environment.unmatchedBehavior == .alwaysAsk)
    #expect(recoveryFailure.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
}

@Test @MainActor func modelStoreFailureRetainsDurableTerminalHistoryInsteadOfCompactingItInMemory() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = AtomicPendingRequestStore(directory: directory)
    let requestID = UUID()
    let history = HistoryEntry(
        id: requestID,
        requestID: requestID,
        sanitizedURL: URL(string: "https://example.com/private")!,
        sourceBundleIdentifier: nil,
        sourceDisplayName: "Unknown",
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
    try await store.save(PendingRequestSnapshot(
        pendingRequests: [],
        terminalRecords: [TerminalRequestRecord(
            requestID: requestID,
            outcome: .succeeded,
            historyEntry: history,
            completedAt: Date(timeIntervalSince1970: 101)
        )]
    ))
    let composition = ProductionAppComposition.makeForTesting(
        modelContainerFactory: { throw TestCompositionFailure.unavailable },
        recoveryStoreFactory: { store }
    )

    await composition.finishLaunchingOnce()
    await composition.linkIntakeService.waitForDrainForTesting()

    let terminal = try #require(await composition.recoveryQueue.terminalSnapshot().first)
    #expect(terminal.requestID == requestID)
    #expect(terminal.historyEntry == nil)
    #expect(composition.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
}

@Test @MainActor func unavailableProductionRecoveryStoreNeverTreatsMemoryAsDurable() async throws {
    let buffer = BootstrapLinkBuffer()
    let composition = ProductionAppComposition.makeForTesting(
        bootstrapBuffer: buffer,
        modelContainerFactory: { try ModelContainerFactory.make(inMemory: true) },
        recoveryStoreFactory: { throw TestCompositionFailure.unavailable }
    )
    composition.linkIntakeService.capture(
        url: URL(string: "https://must-remain-buffered.example/private?token=secret")!,
        senderPID: nil
    )

    await composition.finishLaunchingOnce()
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(buffer.snapshot().count == 1)
    #expect(await composition.recoveryQueue.snapshot().isEmpty)
    #expect(composition.linkIntakeService.workerStartCount == 0)
    #expect(composition.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
}

@Test @MainActor func failedRestoreNeverStartsDrainEvenWhenLaterSavesCouldSucceed() async {
    let store = FailingLoadStore()
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    buffer.capture(URL(string: "https://must-wait-for-restore.example/private?token=secret")!, senderPID: nil)
    let graph = TestLaunchGraph(queue: queue, buffer: buffer)
    let composition = ProductionAppComposition(
        environment: graph.environment,
        recoveryQueue: queue,
        warningSource: nil,
        bootstrapBuffer: buffer,
        linkRoutingCoordinator: graph.coordinator,
        linkIntakeService: graph.intake,
        defaultBrowserService: DefaultBrowserService(
            client: NoopDefaultHandlerClient(),
            applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
            bundleIdentifier: "com.prism.app"
        ),
        loginItemService: LoginItemService(client: NoopLoginItemClient())
    )

    await composition.finishLaunchingOnce()
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(await store.loadCount == 1)
    #expect(await store.saveCount == 0)
    #expect(buffer.snapshot().count == 1)
    #expect(await queue.snapshot().isEmpty)
    #expect(composition.linkIntakeService.workerStartCount == 0)
    #expect(composition.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
}

@Test @MainActor func failedInitialRestoreCanBeExplicitlyRetriedWithoutLosingFIFO() async throws {
    let old = LinkRequest.fixture(id: UUID(), url: "https://old.example")
    let store = ScriptedRestorationStore(
        snapshot: .init(pendingRequests: [old], terminalRecords: []),
        failingLoadCalls: [1]
    )
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    buffer.capture(URL(string: "https://new-one.example")!, senderPID: nil)
    buffer.capture(URL(string: "https://new-two.example")!, senderPID: nil)
    let graph = TestLaunchGraph(queue: queue, buffer: buffer)
    let composition = makeComposition(graph: graph, queue: queue, buffer: buffer)

    await composition.finishLaunchingOnce()

    #expect(await store.loadCount == 1)
    #expect(composition.linkIntakeService.workerStartCount == 0)
    #expect(buffer.snapshot().map(\.url.host) == ["new-one.example", "new-two.example"])
    #expect(await queue.snapshot().isEmpty)

    let restored = await composition.retryRestorationAfterUserAction()
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(restored)
    #expect(await store.loadCount == 2)
    #expect(composition.linkIntakeService.workerStartCount == 1)
    let queuedHosts = await queue.snapshot().map { $0.url.host }
    #expect(queuedHosts == [
        "old.example",
        "new-one.example",
        "new-two.example"
    ])
    #expect(buffer.snapshot().isEmpty)
}

@Test @MainActor func recoveryStoreFactoryFailureReconnectsTheSameQueueOnExplicitRetry() async throws {
    let old = LinkRequest.fixture(id: UUID(), url: "https://old-factory.example")
    let backing = ScriptedRestorationStore(snapshot: .init(
        pendingRequests: [old],
        terminalRecords: []
    ))
    let factory = ScriptedRecoveryStoreFactory(outcomes: [
        .failure,
        .success(backing)
    ])
    let buffer = BootstrapLinkBuffer()
    buffer.capture(URL(string: "https://new-factory.example")!, senderPID: nil)
    let composition = ProductionAppComposition.makeForTesting(
        bootstrapBuffer: buffer,
        modelContainerFactory: { try ModelContainerFactory.make(inMemory: true) },
        recoveryStoreFactory: { try factory.make() }
    )
    let queue = composition.recoveryQueue

    await composition.finishLaunchingOnce()

    #expect(factory.callCount == 1)
    #expect(composition.recoveryQueue === queue)
    #expect(composition.linkIntakeService.workerStartCount == 0)
    #expect(buffer.snapshot().map(\.url.host) == ["new-factory.example"])

    let restored = await composition.retryRestorationAfterUserAction()
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(restored)
    #expect(factory.callCount == 2)
    #expect(composition.recoveryQueue === queue)
    #expect(composition.linkIntakeService.workerStartCount == 1)
    #expect(await queue.snapshot().map(\.url.host) == [
        "old-factory.example",
        "new-factory.example"
    ])
    #expect(buffer.snapshot().isEmpty)
}

@Test @MainActor func concurrentRestorationRetriesShareOneAttemptAndOneWorker() async throws {
    let old = LinkRequest.fixture(id: UUID(), url: "https://old-concurrent.example")
    let store = ScriptedRestorationStore(
        snapshot: .init(pendingRequests: [old], terminalRecords: []),
        failingLoadCalls: [1],
        suspendedLoadCalls: [2]
    )
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    buffer.capture(URL(string: "https://new-concurrent.example")!, senderPID: nil)
    let graph = TestLaunchGraph(queue: queue, buffer: buffer)
    let composition = makeComposition(graph: graph, queue: queue, buffer: buffer)
    await composition.finishLaunchingOnce()

    let firstRetry = Task { @MainActor in
        await composition.retryRestorationAfterUserAction()
    }
    await store.waitUntilLoadSuspended(call: 2)
    let secondRetry = Task { @MainActor in
        await composition.retryRestorationAfterUserAction()
    }
    await Task.yield()

    #expect(await store.loadCount == 2)
    await store.releaseSuspendedLoad(call: 2)
    #expect(await firstRetry.value)
    #expect(await secondRetry.value)
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(await store.loadCount == 2)
    #expect(composition.linkIntakeService.workerStartCount == 1)
    #expect(await queue.snapshot().map(\.url.host) == [
        "old-concurrent.example",
        "new-concurrent.example"
    ])

    #expect(await composition.retryRestorationAfterUserAction())
    #expect(await store.loadCount == 2)
    #expect(composition.linkIntakeService.workerStartCount == 1)
}

@Test @MainActor func failedRestorationRetryCanBeRetriedAgain() async throws {
    let old = LinkRequest.fixture(id: UUID(), url: "https://old-third-attempt.example")
    let store = ScriptedRestorationStore(
        snapshot: .init(pendingRequests: [old], terminalRecords: []),
        failingLoadCalls: [1, 2]
    )
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    buffer.capture(URL(string: "https://new-third-attempt.example")!, senderPID: nil)
    let graph = TestLaunchGraph(queue: queue, buffer: buffer)
    let composition = makeComposition(graph: graph, queue: queue, buffer: buffer)

    await composition.finishLaunchingOnce()
    #expect(!(await composition.retryRestorationAfterUserAction()))

    #expect(await store.loadCount == 2)
    #expect(composition.linkIntakeService.workerStartCount == 0)
    #expect(buffer.snapshot().count == 1)

    #expect(await composition.retryRestorationAfterUserAction())
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(await store.loadCount == 3)
    #expect(composition.linkIntakeService.workerStartCount == 1)
    #expect(await queue.snapshot().map(\.url.host) == [
        "old-third-attempt.example",
        "new-third-attempt.example"
    ])
    #expect(composition.environment.persistenceWarnings.filter {
        $0 == .recoveryStoreUnavailable
    }.count == 1)
}

@Test @MainActor func capturesDuringSuspendedRestoreRemainAfterRestoredFIFO() async throws {
    let firstOld = LinkRequest.fixture(id: UUID(), url: "https://old-one.example")
    let secondOld = LinkRequest.fixture(id: UUID(), url: "https://old-two.example")
    let store = ScriptedRestorationStore(
        snapshot: .init(pendingRequests: [firstOld, secondOld], terminalRecords: []),
        suspendedLoadCalls: [1]
    )
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    let graph = TestLaunchGraph(queue: queue, buffer: buffer)
    let composition = makeComposition(graph: graph, queue: queue, buffer: buffer)

    let launch = Task { @MainActor in
        await composition.finishLaunchingOnce()
    }
    await store.waitUntilLoadSuspended(call: 1)
    composition.linkIntakeService.capture(
        url: URL(string: "https://new-one.example")!,
        senderPID: 1
    )
    composition.linkIntakeService.capture(
        url: URL(string: "https://new-two.example")!,
        senderPID: 2
    )
    await store.releaseSuspendedLoad(call: 1)
    await launch.value
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(await queue.snapshot().map(\.url.host) == [
        "old-one.example",
        "old-two.example",
        "new-one.example",
        "new-two.example"
    ])
    #expect(composition.linkIntakeService.workerStartCount == 1)
}

@Test @MainActor func persistenceRestorationRetryNeverHandsOffUntilRoutingIsExplicitlyResumed() async throws {
    let old = LinkRequest.fixture(id: UUID(), url: "https://automatic-old.example")
    let store = ScriptedRestorationStore(
        snapshot: .init(pendingRequests: [old], terminalRecords: []),
        failingLoadCalls: [1]
    )
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    buffer.capture(URL(string: "https://automatic-new.example")!, senderPID: nil)
    let launcher = CountingBrowserLauncher()
    let graph = TestLaunchGraph(
        queue: queue,
        buffer: buffer,
        automaticBrowserID: "com.apple.Safari",
        browserCatalog: SingleBrowserCatalog(),
        browserLauncher: launcher
    )
    let composition = makeComposition(graph: graph, queue: queue, buffer: buffer)

    await composition.finishLaunchingOnce()
    #expect(launcher.handoffCount == 0)
    #expect(await composition.retryRestorationAfterUserAction())
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(launcher.handoffCount == 0)
    #expect(await queue.snapshot().map(\.url.host) == [
        "automatic-old.example",
        "automatic-new.example"
    ])
    #expect(composition.linkIntakeService.workerStartCount == 1)

    await composition.resumeRoutingAfterRecoveryUserAction()
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(launcher.handoffCount == 2)
    #expect(await queue.next() == nil)
    #expect(composition.linkIntakeService.workerStartCount == 1)
}

@Test @MainActor func failedNormalStartupEnqueueBuffersNewLinksUntilPersistenceRetryThenRoutingResume() async throws {
    let store = ScriptedRestorationStore(failingSaveCalls: [1])
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    buffer.capture(URL(string: "https://automatic-after-save.example")!, senderPID: nil)
    let launcher = CountingBrowserLauncher()
    let graph = TestLaunchGraph(
        queue: queue,
        buffer: buffer,
        automaticBrowserID: "com.apple.Safari",
        browserCatalog: SingleBrowserCatalog(),
        browserLauncher: launcher
    )
    let composition = makeComposition(graph: graph, queue: queue, buffer: buffer)

    await composition.finishLaunchingOnce()
    await composition.linkIntakeService.waitForDrainForTesting()

    composition.linkIntakeService.capture(
        url: URL(string: "https://second-after-failure.example")!,
        senderPID: nil
    )
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(launcher.handoffCount == 0)
    #expect(buffer.snapshot().map(\.url.host) == [
        "automatic-after-save.example",
        "second-after-failure.example"
    ])
    #expect(await queue.snapshot().isEmpty)
    #expect(composition.linkIntakeService.workerStartCount == 1)

    composition.linkIntakeService.retryPendingPersistenceAfterUserAction()
    await composition.linkIntakeService.waitForDrainForTesting()

    #expect(launcher.handoffCount == 0)
    #expect(buffer.snapshot().isEmpty)
    #expect(await queue.snapshot().map(\.url.host) == [
        "automatic-after-save.example",
        "second-after-failure.example"
    ])
    #expect(composition.linkIntakeService.workerStartCount == 2)

    await composition.resumeRoutingAfterRecoveryUserAction()

    #expect(launcher.handoffCount == 2)
    #expect(await queue.next() == nil)
    #expect(composition.linkIntakeService.workerStartCount == 2)
}

@Test @MainActor func productionCompositionRestoresOnlyOnce() async {
    let store = CountingLoadStore()
    let composition = ProductionAppComposition(
        environment: AppEnvironment.preview,
        recoveryQueue: LinkRequestQueue(store: store),
        warningSource: nil
    )

    await composition.restoreOnce()
    await composition.restoreOnce()

    #expect(await store.loadCount == 1)
}

@Test @MainActor func productionCompositionConnectsOneSharedLinkGraph() throws {
    let buffer = BootstrapLinkBuffer()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let composition = ProductionAppComposition.makeForTesting(
        bootstrapBuffer: buffer,
        modelContainerFactory: { try ModelContainerFactory.make(inMemory: true) },
        recoveryStoreFactory: { AtomicPendingRequestStore(directory: directory) }
    )

    #expect(composition.environment.linkIntakeService === composition.linkIntakeService)
    #expect(composition.environment.linkRoutingCoordinator === composition.linkRoutingCoordinator)
    #expect(composition.environment.defaultBrowserService === composition.defaultBrowserService)
    #expect(composition.environment.loginItemService === composition.loginItemService)
    #expect(composition.bootstrapBuffer === buffer)
    #expect(composition.environment.persistenceWarnings.isEmpty)
    #expect(composition.selectorPresentationRelay.target === composition.windowCoordinator)
}

@Test @MainActor func appDelegateSynchronouslyBuffersOnlyWebURLsAndCopiedSenderPID() async throws {
    let buffer = BootstrapLinkBuffer()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let composition = ProductionAppComposition.makeForTesting(
        bootstrapBuffer: buffer,
        modelContainerFactory: { try ModelContainerFactory.make(inMemory: true) },
        recoveryStoreFactory: { AtomicPendingRequestStore(directory: directory) }
    )
    let delegate = AppDelegate(
        composition: composition,
        copyCurrentSenderPID: { 321 }
    )

    delegate.application(NSApplication.shared, open: [
        URL(string: "https://one.example/private?token=secret")!,
        URL(string: "file:///private/secret.txt")!,
        URL(string: "http://two.example")!
    ])

    #expect(delegate.environment === composition.environment)
    #expect(buffer.snapshot().map(\.url.host) == ["one.example", "two.example"])
    #expect(buffer.snapshot().map(\.senderPID) == [321, 321])
    #expect(buffer.snapshot().map(\.sequence) == [0, 1])
    #expect(await composition.recoveryQueue.snapshot().isEmpty)
}

@Test @MainActor func compositionFinishesRestoreBeforeBufferedLinksAndStartsOnce() async throws {
    let old = LinkRequest.fixture(url: "https://old.example")
    let store = CountingLoadStore(snapshot: .init(pendingRequests: [old], terminalRecords: []))
    let queue = LinkRequestQueue(store: store)
    let buffer = BootstrapLinkBuffer()
    buffer.capture(URL(string: "https://new.example")!, senderPID: nil)
    let graph = TestLaunchGraph(queue: queue, buffer: buffer)
    let composition = ProductionAppComposition(
        environment: graph.environment,
        recoveryQueue: queue,
        warningSource: nil,
        bootstrapBuffer: buffer,
        linkRoutingCoordinator: graph.coordinator,
        linkIntakeService: graph.intake,
        defaultBrowserService: DefaultBrowserService(
            client: NoopDefaultHandlerClient(),
            applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
            bundleIdentifier: "com.prism.app"
        ),
        loginItemService: LoginItemService(client: NoopLoginItemClient())
    )

    await composition.finishLaunchingOnce()
    await composition.finishLaunchingOnce()
    try await graph.intake.drainForTesting()

    #expect(await queue.snapshot().map(\.url.host) == ["old.example", "new.example"])
    #expect(await store.loadCount == 1)
    #expect(composition.finishLaunchCount == 1)
    #expect(graph.intake.workerStartCount == 1)
}

#if DEBUG
@Test @MainActor func sourceProbeWritesOnlyApprovedDiagnosticFields() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appending(path: "source-probe.jsonl")
    let recorder = SourceProbeRecorder(fileURL: fileURL)
    recorder.record(LinkCaptureDiagnostic(
        timestamp: Date(timeIntervalSince1970: 100),
        sourceDisplayName: "Safari",
        sourceBundleIdentifier: "com.apple.Safari",
        senderPIDPresent: true,
        confidence: .confirmed
    ))

    try recorder.appendEvidence(
        expectedSource: "Safari",
        runState: .cold,
        passed: true
    )

    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(contents.contains("com.apple.Safari"))
    #expect(contents.contains("\"runState\":\"cold\""))
    #expect(!contents.contains("http://"))
    #expect(!contents.contains("https://"))
    #expect(!contents.contains("token="))
    #expect(!contents.contains("message"))
}

@Test @MainActor func sourceProbeNeverRecordsAnUnconfirmedOrMismatchedResultAsPassing() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appending(path: "source-probe.jsonl")
    let recorder = SourceProbeRecorder(fileURL: fileURL)
    recorder.record(LinkCaptureDiagnostic(
        timestamp: Date(timeIntervalSince1970: 100),
        sourceDisplayName: "Observed Source",
        sourceBundleIdentifier: "com.example.observed",
        senderPIDPresent: false,
        confidence: .low
    ))

    try recorder.appendEvidence(
        expectedSource: "Safari",
        runState: .warm,
        passed: true
    )

    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(contents.contains("\"passed\":false"))
    #expect(!contents.contains("\"passed\":true"))
}

@Test @MainActor func sourceProbeRejectsFreeformTextOutsideTheEvidenceMatrix() {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appending(path: "source-probe.jsonl")
    let recorder = SourceProbeRecorder(fileURL: fileURL)
    recorder.record(LinkCaptureDiagnostic(
        timestamp: Date(timeIntervalSince1970: 100),
        sourceDisplayName: "Safari",
        sourceBundleIdentifier: "com.apple.Safari",
        senderPIDPresent: true,
        confidence: .confirmed
    ))

    #expect(throws: SourceProbeRecorderError.self) {
        try recorder.appendEvidence(
            expectedSource: "This could be pasted private text",
            runState: .warm,
            passed: true
        )
    }
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
}
#endif

private enum TestCompositionFailure: Error {
    case unavailable
}

private actor CountingLoadStore: PendingRequestStore {
    private var snapshot: PendingRequestSnapshot
    private(set) var loadCount = 0

    init(snapshot: PendingRequestSnapshot = .init(pendingRequests: [], terminalRecords: [])) {
        self.snapshot = snapshot
    }

    func load() async throws -> PendingRequestSnapshot {
        loadCount += 1
        return snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        self.snapshot = snapshot
    }
}

private actor FailingLoadStore: PendingRequestStore {
    private(set) var loadCount = 0
    private(set) var saveCount = 0

    func load() async throws -> PendingRequestSnapshot {
        loadCount += 1
        throw TestCompositionFailure.unavailable
    }

    func save(_: PendingRequestSnapshot) async throws {
        saveCount += 1
    }
}

private actor ScriptedRestorationStore: PendingRequestStore, PersistenceWarningSource {
    private var snapshot: PendingRequestSnapshot
    private var failingLoadCalls: Set<Int>
    private var failingSaveCalls: Set<Int>
    private var suspendedLoadCalls: Set<Int>
    private var activeSuspendedLoadCalls: Set<Int> = []
    private var suspendedLoadContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var suspendedLoadObservers: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var loadCount = 0
    private(set) var saveCount = 0

    init(
        snapshot: PendingRequestSnapshot = .init(pendingRequests: [], terminalRecords: []),
        failingLoadCalls: Set<Int> = [],
        failingSaveCalls: Set<Int> = [],
        suspendedLoadCalls: Set<Int> = []
    ) {
        self.snapshot = snapshot
        self.failingLoadCalls = failingLoadCalls
        self.failingSaveCalls = failingSaveCalls
        self.suspendedLoadCalls = suspendedLoadCalls
    }

    func load() async throws -> PendingRequestSnapshot {
        loadCount += 1
        let call = loadCount
        if suspendedLoadCalls.remove(call) != nil {
            activeSuspendedLoadCalls.insert(call)
            let observers = suspendedLoadObservers.removeValue(forKey: call) ?? []
            observers.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                suspendedLoadContinuations[call] = continuation
            }
            activeSuspendedLoadCalls.remove(call)
        }
        if failingLoadCalls.remove(call) != nil {
            throw TestCompositionFailure.unavailable
        }
        return snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        saveCount += 1
        if failingSaveCalls.remove(saveCount) != nil {
            throw TestCompositionFailure.unavailable
        }
        self.snapshot = snapshot
    }

    func drainPersistenceWarnings() async -> [PersistenceWarning] { [] }

    func waitUntilLoadSuspended(call: Int) async {
        if activeSuspendedLoadCalls.contains(call) { return }
        await withCheckedContinuation { continuation in
            suspendedLoadObservers[call, default: []].append(continuation)
        }
    }

    func releaseSuspendedLoad(call: Int) {
        suspendedLoadContinuations.removeValue(forKey: call)?.resume()
    }
}

@MainActor
private final class ScriptedRecoveryStoreFactory {
    enum Outcome {
        case failure
        case success(any PendingRequestStore & PersistenceWarningSource)
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func make() throws -> any PendingRequestStore & PersistenceWarningSource {
        callCount += 1
        switch outcomes.removeFirst() {
        case .failure:
            throw TestCompositionFailure.unavailable
        case let .success(store):
            return store
        }
    }
}

@MainActor
private struct TestLaunchGraph {
    let environment: AppEnvironment
    let presenter: SelectorPresentationRelay
    let coordinator: LinkRoutingCoordinator
    let intake: LinkIntakeService

    init(
        queue: LinkRequestQueue,
        buffer: BootstrapLinkBuffer,
        automaticBrowserID: BrowserID? = nil,
        browserCatalog: (any BrowserCataloging)? = nil,
        browserLauncher: (any BrowserLaunching)? = nil
    ) {
        let rules = InMemoryRuleRepository()
        let history = InMemoryHistoryRepository()
        let browserPreferences = InMemoryBrowserPreferenceRepository()
        var appSettings = AppSettings.defaults
        if let automaticBrowserID {
            appSettings.unmatchedBehavior = .preferredBrowser
            appSettings.preferredBrowserID = automaticBrowserID
        }
        let settings = InMemorySettingsRepository(settings: appSettings)
        environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: rules,
            historyRepository: history,
            browserPreferenceRepository: browserPreferences,
            settingsRepository: settings
        )
        presenter = SelectorPresentationRelay()
        coordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: rules,
            historyRepository: history,
            settingsRepository: settings,
            browserCatalog: browserCatalog ?? EmptyBrowserCatalog(),
            browserLauncher: browserLauncher ?? NoopBrowserLauncher(),
            sourceManifest: .disabled,
            presenter: presenter,
            warningPresenter: environment
        )
        intake = LinkIntakeService(
            queue: queue,
            bootstrap: buffer,
            sourceAttributor: UnknownSourceAttributor(),
            lastActivatedSource: { nil },
            coordinator: coordinator,
            warningPresenter: environment
        )
        coordinator.continuationRequester = intake
        environment.connectLinkRouting(
            coordinator: coordinator,
            intake: intake,
            defaultBrowserService: nil,
            loginItemService: nil
        )
    }
}

@MainActor
private func makeComposition(
    graph: TestLaunchGraph,
    queue: LinkRequestQueue,
    buffer: BootstrapLinkBuffer
) -> ProductionAppComposition {
    ProductionAppComposition(
        environment: graph.environment,
        recoveryQueue: queue,
        warningSource: nil,
        bootstrapBuffer: buffer,
        linkRoutingCoordinator: graph.coordinator,
        linkIntakeService: graph.intake,
        defaultBrowserService: DefaultBrowserService(
            client: NoopDefaultHandlerClient(),
            applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
            bundleIdentifier: "com.prism.app"
        ),
        loginItemService: LoginItemService(client: NoopLoginItemClient())
    )
}

@MainActor
private final class EmptyBrowserCatalog: BrowserCataloging {
    func scan() async throws -> [BrowserDescriptor] { [] }
}

@MainActor
private final class NoopBrowserLauncher: BrowserLaunching {
    func open(_: URL, with _: BrowserDescriptor) async throws -> BrowserLaunchResult {
        .handoffSucceeded
    }
}

@MainActor
private final class CountingBrowserLauncher: BrowserLaunching {
    private(set) var handoffCount = 0

    func open(_: URL, with _: BrowserDescriptor) async throws -> BrowserLaunchResult {
        handoffCount += 1
        return .handoffSucceeded
    }
}

@MainActor
private final class SingleBrowserCatalog: BrowserCataloging {
    func scan() async throws -> [BrowserDescriptor] {
        [BrowserDescriptor(
            id: "com.apple.Safari",
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            applicationURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            securityScopedBookmark: nil,
            origin: .system,
            availability: .available,
            selectorOrder: 0
        )]
    }
}

@MainActor
private final class UnknownSourceAttributor: SourceAttributing {
    func resolve(senderPID _: Int32?, lastActivated _: SourceApplication?) -> SourceApplication {
        .unknown
    }
}

@MainActor
private final class NoopDefaultHandlerClient: DefaultHandlerClient {
    func handlerBundleIdentifier(forScheme _: String) -> String? { nil }
    func setDefault(applicationURL _: URL, forScheme _: String) async throws {}
}

@MainActor
private final class NoopLoginItemClient: LoginItemClient {
    func status() -> LoginItemClientStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettingsLoginItems() {}
}
