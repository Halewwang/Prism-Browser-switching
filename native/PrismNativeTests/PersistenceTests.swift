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

@Test @MainActor func ruleRepositoryRoundTripsVersionedMatchersAndSortsByTypeThenPriority() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let repository = SwiftDataRuleRepository(container: result.container)
    let lowExact = routingRule(matcher: .exactHost("example.com"), priority: 1)
    let highExact = routingRule(matcher: .exactHost("prism.app"), priority: 9)
    let contains = routingRule(matcher: .urlContains("campaign"), priority: 100)
    let source = routingRule(matcher: .sourceBundleIdentifier("com.example.source"), priority: 100)

    try [source, lowExact, contains, highExact].forEach(repository.upsert)

    #expect(try repository.all() == [highExact, lowExact, contains, source])
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

    let result = try ModelContainerFactory.makeForTesting(
        inMemory: false,
        storeURL: storeURL,
        simulateInitialOpenFailure: true
    )

    guard case let .corruptStoreRecovered(backupLocation)? = result.warning else {
        Issue.record("Expected a safe-mode recovery warning")
        return
    }
    #expect(FileManager.default.fileExists(atPath: backupLocation))
    #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: backupLocation).appending(path: "PrismNative.store").path))
    let settings = try SwiftDataSettingsRepository(container: result.container).load()
    #expect(settings.automaticRulesEnabled == false)
    #expect(settings.unmatchedBehavior == .alwaysAsk)
    #expect(settings.schemaVersion == 1)
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

private func routingRule(matcher: RuleMatcher, priority: Int) -> RoutingRule {
    RoutingRule(
        id: UUID(),
        isEnabled: true,
        matcher: matcher,
        targetBrowserID: "com.apple.Safari",
        priority: priority,
        label: nil,
        createdAt: .now,
        updatedAt: .now
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
