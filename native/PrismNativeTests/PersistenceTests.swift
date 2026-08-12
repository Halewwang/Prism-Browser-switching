import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func pendingStoreRestoresCompleteURLUntilCompletion() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = AtomicPendingRequestStore(directory: directory)
    let request = LinkRequest.fixture(url: "https://example.com/private?token=kept-until-complete")

    try await store.save(PendingRequestSnapshot(pendingRequests: [request], terminalRecords: []))
    let restored = try await store.load()

    #expect(restored.pendingRequests == [request])
    #expect(restored.terminalRecords.isEmpty)
}

@Test @MainActor func corruptPendingStoreCreatesBackupAndReturnsExplicitWarning() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let recoveryFile = directory.appending(path: "pending-requests-v1.json")
    try Data("not valid JSON".utf8).write(to: recoveryFile)
    let store = AtomicPendingRequestStore(directory: directory)

    let restored = try await store.load()
    let warnings = await store.drainPersistenceWarnings()

    #expect(restored == PendingRequestSnapshot(pendingRequests: [], terminalRecords: []))
    #expect(warnings.count == 1)
    guard case let .corruptStoreRecovered(backupLocation) = warnings[0] else {
        Issue.record("Expected a corrupt-store recovery warning")
        return
    }
    #expect(FileManager.default.fileExists(atPath: backupLocation))
    #expect(FileManager.default.fileExists(atPath: recoveryFile.path))
    #expect((try await store.load()) == PendingRequestSnapshot(pendingRequests: [], terminalRecords: []))
}

@Test @MainActor func historyRepositoryStoresOnlySanitizedURLs() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let repository = SwiftDataHistoryRepository(container: result.container)
    let entry = historyEntry(url: "https://example.com/private?token=secret&safe=kept")

    try repository.upsert(entry)
    let restored = try repository.recent(limit: 10, newerThan: .distantPast)

    #expect(restored.count == 1)
    #expect(restored[0].sanitizedURL?.absoluteString == "https://example.com/private?safe=kept")
}

@Test @MainActor func historyFailureReasonsNeverPersistOriginalURLsOrTokens() throws {
    var entry = historyEntry(url: "https://example.com/safe")
    let privateReason = "Launch failed for https://example.com/private?token=do-not-store"
    entry.failureReason = privateReason

    let record = HistoryRecord(entry: entry)
    let roundTripped = try record.historyEntry()

    #expect(record.failureReason == "launch_failed")
    #expect(roundTripped.failureReason == "launch_failed")
    #expect(!(record.failureReason?.contains("token=do-not-store") ?? false))
    #expect(!(roundTripped.failureReason?.contains("https://example.com/private") ?? false))
}

@Test @MainActor func historyRepositoryEnforcesCutoffAndLimit() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let repository = SwiftDataHistoryRepository(container: result.container)
    let now = Date(timeIntervalSince1970: 1_000)
    let expired = historyEntry(id: UUID(), createdAt: now.addingTimeInterval(-100), url: "https://example.com/expired")
    let oldestRetained = historyEntry(id: UUID(), createdAt: now.addingTimeInterval(-20), url: "https://example.com/old")
    let newestRetained = historyEntry(id: UUID(), createdAt: now.addingTimeInterval(-10), url: "https://example.com/new")
    let beyondLimit = historyEntry(id: UUID(), createdAt: now.addingTimeInterval(-5), url: "https://example.com/newest")

    try [expired, oldestRetained, newestRetained, beyondLimit].forEach(repository.upsert)
    try repository.enforceRetention(limit: 2, cutoff: now.addingTimeInterval(-30))

    let restored = try repository.recent(limit: 10, newerThan: .distantPast)
    #expect(restored.map(\.id) == [beyondLimit.id, newestRetained.id])
}

@Test @MainActor func ruleRepositoryUsesSharedURLThenSourcePriorityAndIDOrdering() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let repository = SwiftDataRuleRepository(container: result.container)
    let source = routingRule(id: fixedUUID(1), matcher: .sourceBundleIdentifier("com.example.source"), priority: 0)
    let exact = routingRule(id: fixedUUID(5), matcher: .exactHost("example.com"), priority: 5)
    let subdomain = routingRule(id: fixedUUID(4), matcher: .hostAndSubdomains("example.com"), priority: 1)
    let contains = routingRule(id: fixedUUID(3), matcher: .urlContains("example"), priority: 1)

    try [source, exact, subdomain, contains].forEach(repository.upsert)

    #expect(try repository.all() == [contains, subdomain, exact, source])
}

@Test @MainActor func browserPreferencesKeepOrderAndCustomBookmarksWithoutAvailabilityScanResults() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let repository = SwiftDataBrowserPreferenceRepository(container: result.container)
    let custom = BrowserDescriptor(
        id: "com.example.custom",
        bundleIdentifier: "com.example.custom",
        displayName: "Custom",
        applicationURL: URL(fileURLWithPath: "/Applications/Custom.app"),
        securityScopedBookmark: Data([1, 2, 3]),
        origin: .custom,
        availability: .available,
        selectorOrder: 0
    )

    try repository.upsertCustomBrowser(custom)
    try repository.saveOrder(["com.apple.Safari", custom.id])

    #expect(try repository.orderedBrowserIDs() == ["com.apple.Safari", custom.id])
    let restored = try repository.customBrowsers()
    #expect(restored.count == 1)
    #expect(restored[0].id == custom.id)
    #expect(restored[0].applicationURL == custom.applicationURL)
    #expect(restored[0].securityScopedBookmark == custom.securityScopedBookmark)
    #expect(restored[0].availability == .unavailable)
}

@Test @MainActor func settingsRepositoryUsesVersionOneDefaults() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let repository = SwiftDataSettingsRepository(container: result.container)

    #expect(try repository.load() == .defaults)
    var settings = AppSettings.defaults
    settings.historyEnabled = false
    settings.unmatchedBehavior = .preferredBrowser
    settings.schemaVersion = 99
    try repository.save(settings)

    let restored = try repository.load()
    #expect(restored.historyEnabled == false)
    #expect(restored.unmatchedBehavior == .preferredBrowser)
    #expect(restored.schemaVersion == 1)
}

@Test @MainActor func containerRecoveryPreservesCorruptArtifactsAndUsesSafeSettings() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let storeURL = directory.appending(path: "PrismNative.store")
    try Data("corrupt data".utf8).write(to: storeURL)
    try Data("shared memory".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-shm"))
    try Data("write ahead log".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))

    let result = try ModelContainerFactory.makeForTesting(
        inMemory: false,
        storeURL: storeURL,
        simulatedOpenFailures: 1
    )

    guard case let .corruptStoreRecovered(backupLocation)? = result.warning else {
        Issue.record("Expected a safe-mode recovery warning")
        return
    }
    #expect(FileManager.default.fileExists(atPath: backupLocation))
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: backupLocation).appending(path: "PrismNative.store").path))
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: backupLocation).appending(path: "PrismNative.store-shm").path))
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: backupLocation).appending(path: "PrismNative.store-wal").path))
    let settings = try SwiftDataSettingsRepository(container: result.container).load()
    #expect(settings.automaticRulesEnabled == false)
    #expect(settings.unmatchedBehavior == .alwaysAsk)
    #expect(settings.schemaVersion == 1)
}

@Test @MainActor func realCorruptStoreOpenPreservesTheStoreBeforeCreatingSafeModeContainer() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let storeURL = directory.appending(path: "PrismNative.store")
    try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)

    let result = try ModelContainerFactory.makeForTesting(inMemory: false, storeURL: storeURL)

    guard case let .corruptStoreRecovered(backupLocation)? = result.warning else {
        Issue.record("Expected a recovery notice after a real persistent-store open failure")
        return
    }
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: backupLocation).appending(path: "PrismNative.store").path))
}

@Test @MainActor func inMemoryContainerOpenFailureDoesNotCreateBackup() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    #expect(throws: Error.self) {
        try ModelContainerFactory.makeForTesting(
            inMemory: true,
            storeURL: directory.appending(path: "PrismNative.store"),
            simulatedOpenFailures: 1
        )
    }
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "CorruptDataBackup").path))
}

@Test @MainActor func secondPersistentContainerOpenFailureIsPropagated() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    #expect(throws: Error.self) {
        try ModelContainerFactory.makeForTesting(
            inMemory: false,
            storeURL: directory.appending(path: "PrismNative.store"),
            simulatedOpenFailures: 2
        )
    }
}

@Test @MainActor func defaultRecoveryStoreResolutionFailureDoesNotUseTemporaryDirectory() throws {
    let temporaryProbe = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    #expect(throws: Error.self) {
        try AtomicPendingRequestStore.makeForTesting(resolvingDefaultDirectoryWith: {
            throw TestPersistenceFailure.unavailable
        })
    }
    #expect(!FileManager.default.fileExists(atPath: temporaryProbe.path))
}

@Test @MainActor func reconciliationSavesTerminalHistoryBeforeCompactingJournal() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let request = LinkRequest.fixture()
    let entry = historyEntry(requestID: request.id, url: "https://example.com/safe")
    let history = InMemoryHistoryRepository()
    let environment = AppEnvironment(
        route: .history,
        unmatchedBehavior: .alwaysAsk,
        updateChecker: DisabledUpdateChecker(),
        ruleRepository: InMemoryRuleRepository(),
        historyRepository: history,
        browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
        settingsRepository: InMemorySettingsRepository()
    )
    try await queue.enqueue(request)
    try await queue.markCompleted(request.id, historyEntry: entry)

    await environment.restoreAndReconcile(queue: queue, warningSource: nil)

    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(try history.recent(limit: 10, newerThan: .distantPast) == [entry])
    #expect(environment.persistenceWarnings.isEmpty)
}

@Test @MainActor func reconciliationRetainsTerminalHistoryWhenSavingFails() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let request = LinkRequest.fixture()
    let entry = historyEntry(requestID: request.id, url: "https://example.com/safe")
    let environment = AppEnvironment(
        route: .history,
        unmatchedBehavior: .alwaysAsk,
        updateChecker: DisabledUpdateChecker(),
        ruleRepository: InMemoryRuleRepository(),
        historyRepository: FailingHistoryRepository(),
        browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
        settingsRepository: InMemorySettingsRepository()
    )
    try await queue.enqueue(request)
    try await queue.markCompleted(request.id, historyEntry: entry)

    await environment.restoreAndReconcile(queue: queue, warningSource: nil)

    #expect(await queue.terminalSnapshot().map(\.requestID) == [request.id])
    #expect(environment.persistenceWarnings.contains(.historyNotSaved))
}

@Test @MainActor func reconciliationStopsImmediatelyWhenRecoveryStoreCannotRestore() async {
    let settings = CountingSettingsRepository()
    let environment = makeEnvironment(settingsRepository: settings)
    let queue = LinkRequestQueue(store: FailingLoadStore())
    let warnings = CountingWarningSource([.corruptStoreRecovered(backupLocation: "/unused")])

    await environment.restoreAndReconcile(queue: queue, warningSource: warnings)

    #expect(environment.persistenceWarnings == [.recoveryStoreUnavailable])
    #expect(settings.loadCount == 0)
    #expect(await warnings.drainCount == 0)
}

@Test @MainActor func reconciliationDrainsRecoveryWarningsAfterRestore() async {
    let environment = makeEnvironment()
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    let warnings = CountingWarningSource([.corruptStoreRecovered(backupLocation: "/recovery-backup")])

    await environment.restoreAndReconcile(queue: queue, warningSource: warnings)

    #expect(environment.persistenceWarnings == [.corruptStoreRecovered(backupLocation: "/recovery-backup")])
    #expect(await warnings.drainCount == 1)
}

@Test @MainActor func reconciliationUsesAlwaysAskAndHistoryEnabledWhenSettingsCannotLoad() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let request = LinkRequest.fixture()
    let entry = historyEntry(requestID: request.id, url: "https://example.com/safe")
    let history = InMemoryHistoryRepository()
    let environment = makeEnvironment(
        unmatchedBehavior: .preferredBrowser,
        historyRepository: history,
        settingsRepository: FailingSettingsRepository()
    )
    try await queue.enqueue(request)
    try await queue.markCompleted(request.id, historyEntry: entry)

    await environment.restoreAndReconcile(queue: queue, warningSource: nil)

    #expect(environment.unmatchedBehavior == .alwaysAsk)
    #expect(environment.persistenceWarnings.contains(.settingsNotSaved))
    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(try history.recent(limit: 10, newerThan: .distantPast) == [entry])
}

@Test @MainActor func reconciliationCompactsHistoryDisabledAndEntrylessTerminalRecords() async throws {
    var settings = AppSettings.defaults
    settings.historyEnabled = false
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let first = LinkRequest.fixture()
    let second = LinkRequest.fixture()
    let history = InMemoryHistoryRepository()
    let environment = makeEnvironment(
        historyRepository: history,
        settingsRepository: InMemorySettingsRepository(settings: settings)
    )
    try await queue.enqueue(first)
    try await queue.enqueue(second)
    try await queue.markCompleted(first.id, historyEntry: historyEntry(requestID: first.id, url: "https://example.com/not-saved"))
    try await queue.markCancelled(second.id, historyEntry: nil)

    await environment.restoreAndReconcile(queue: queue, warningSource: nil)

    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(try history.recent(limit: 10, newerThan: .distantPast).isEmpty)
}

@Test @MainActor func reconciliationRetainsJournalWhenTerminalCompactionCannotSave() async throws {
    let store = ControlledPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let request = LinkRequest.fixture()
    let environment = makeEnvironment()
    try await queue.enqueue(request)
    try await queue.markCompleted(request.id, historyEntry: historyEntry(requestID: request.id, url: "https://example.com/safe"))
    await store.failFutureSaves()

    await environment.restoreAndReconcile(queue: queue, warningSource: nil)

    #expect(await queue.terminalSnapshot().map(\.requestID) == [request.id])
    #expect(environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
}

private func historyEntry(
    id: UUID = UUID(),
    requestID: UUID = UUID(),
    createdAt: Date = .now,
    url: String
) -> HistoryEntry {
    HistoryEntry(
        id: id,
        requestID: requestID,
        sanitizedURL: URL(string: url),
        sourceBundleIdentifier: "com.example.source",
        sourceDisplayName: "Source",
        targetBrowserID: "com.apple.Safari",
        targetDisplayName: "Safari",
        method: .manual,
        result: .success,
        matchingRuleID: nil,
        failureReason: nil,
        attemptCount: 1,
        createdAt: createdAt,
        completedAt: createdAt
    )
}

private func routingRule(id: UUID = UUID(), matcher: RuleMatcher, priority: Int) -> RoutingRule {
    RoutingRule(
        id: id,
        isEnabled: true,
        matcher: matcher,
        targetBrowserID: "com.apple.Safari",
        priority: priority,
        label: nil,
        createdAt: .now,
        updatedAt: .now
    )
}

private func fixedUUID(_ value: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
}

@MainActor
private func makeEnvironment(
    unmatchedBehavior: UnmatchedBehavior = .alwaysAsk,
    historyRepository: (any HistoryRepository)? = nil,
    settingsRepository: (any SettingsRepository)? = nil
) -> AppEnvironment {
    AppEnvironment(
        route: .history,
        unmatchedBehavior: unmatchedBehavior,
        updateChecker: DisabledUpdateChecker(),
        ruleRepository: InMemoryRuleRepository(),
        historyRepository: historyRepository ?? InMemoryHistoryRepository(),
        browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
        settingsRepository: settingsRepository ?? InMemorySettingsRepository()
    )
}

@MainActor
private final class FailingHistoryRepository: HistoryRepository {
    private enum Failure: Error { case unavailable }

    func upsert(_: HistoryEntry) throws { throw Failure.unavailable }
    func recent(limit _: Int, newerThan _: Date) throws -> [HistoryEntry] { [] }
    func delete(id _: UUID) throws {}
    func clear() throws {}
    func enforceRetention(limit _: Int, cutoff _: Date) throws {}
}

private enum TestPersistenceFailure: Error {
    case unavailable
}

private actor FailingLoadStore: PendingRequestStore {
    func load() async throws -> PendingRequestSnapshot {
        throw TestPersistenceFailure.unavailable
    }

    func save(_: PendingRequestSnapshot) async throws {}
}

private actor ControlledPendingRequestStore: PendingRequestStore {
    private var snapshot = PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])
    private var failSaves = false

    func load() async throws -> PendingRequestSnapshot {
        snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        guard !failSaves else {
            throw TestPersistenceFailure.unavailable
        }
        self.snapshot = snapshot
    }

    func failFutureSaves() {
        failSaves = true
    }
}

private actor CountingWarningSource: PersistenceWarningSource {
    private var warnings: [PersistenceWarning]
    private(set) var drainCount = 0

    init(_ warnings: [PersistenceWarning]) {
        self.warnings = warnings
    }

    func drainPersistenceWarnings() async -> [PersistenceWarning] {
        drainCount += 1
        defer { warnings.removeAll() }
        return warnings
    }
}

@MainActor
private final class CountingSettingsRepository: SettingsRepository {
    private(set) var loadCount = 0

    func load() throws -> AppSettings {
        loadCount += 1
        return .defaults
    }

    func save(_: AppSettings) throws {}
}

@MainActor
private final class FailingSettingsRepository: SettingsRepository {
    func load() throws -> AppSettings {
        throw TestPersistenceFailure.unavailable
    }

    func save(_: AppSettings) throws {}
}
