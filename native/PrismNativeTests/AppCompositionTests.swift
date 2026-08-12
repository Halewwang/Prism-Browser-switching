import AppKit
import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func productionCompositionFallsBackToSafeEnvironmentWhenPersistenceCannotStart() {
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

    #expect(await composition.recoveryQueue.terminalSnapshot().map(\.requestID) == [requestID])
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

@MainActor
private struct TestLaunchGraph {
    let environment: AppEnvironment
    let presenter: SelectorPresentationRelay
    let coordinator: LinkRoutingCoordinator
    let intake: LinkIntakeService

    init(queue: LinkRequestQueue, buffer: BootstrapLinkBuffer) {
        let rules = InMemoryRuleRepository()
        let history = InMemoryHistoryRepository()
        let browserPreferences = InMemoryBrowserPreferenceRepository()
        let settings = InMemorySettingsRepository()
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
        let browserCatalog = EmptyBrowserCatalog()
        coordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: rules,
            historyRepository: history,
            settingsRepository: settings,
            browserCatalog: browserCatalog,
            browserLauncher: NoopBrowserLauncher(),
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
        environment.connectLinkRouting(
            coordinator: coordinator,
            intake: intake,
            defaultBrowserService: nil,
            loginItemService: nil
        )
    }
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
