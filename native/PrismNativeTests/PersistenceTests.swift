import Foundation
import PrismCore
import SwiftData
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

@Test @MainActor func historyRepositoryMigratesLegacyURLsWithNewlyRecognizedSensitiveFields() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let context = ModelContext(result.container)
    let record = HistoryRecord(entry: historyEntry(url: "https://example.com/private?safe=kept"))
    record.sanitizedURLString = "https://example.com/private?disposable_login_token=redacted&user_code=redacted&safe=kept"
    context.insert(record)
    try context.save()
    let repository = SwiftDataHistoryRepository(container: result.container)

    let restored = try repository.recent(limit: 10, newerThan: .distantPast)
    let persisted = try context.fetch(FetchDescriptor<HistoryRecord>())

    #expect(restored.first?.sanitizedURL?.absoluteString == "https://example.com/private?safe=kept")
    #expect(persisted.first?.sanitizedURLString == "https://example.com/private?safe=kept")
}

@Test @MainActor func historyRepositoryRemovesLegacyNonWebURLsInsteadOfRetainingThem() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let context = ModelContext(result.container)
    let record = HistoryRecord(entry: historyEntry(url: "https://example.com/private?safe=kept"))
    record.sanitizedURLString = "ftp://legacy.example/private?token=redacted"
    context.insert(record)
    try context.save()
    let repository = SwiftDataHistoryRepository(container: result.container)

    let restored = try repository.recent(limit: 10, newerThan: .distantPast)
    let persisted = try context.fetch(FetchDescriptor<HistoryRecord>())

    #expect(restored.first?.sanitizedURL == nil)
    #expect(persisted.first?.sanitizedURLString == nil)
}

@Test @MainActor func historyRepositoryKeepsOneStableRowPerRequestID() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let repository = SwiftDataHistoryRepository(container: result.container)
    let requestID = fixedUUID(700)
    let first = historyEntry(
        id: fixedUUID(701),
        requestID: requestID,
        createdAt: Date(timeIntervalSince1970: 100),
        url: "https://example.com/first"
    )
    var retry = historyEntry(
        id: fixedUUID(702),
        requestID: requestID,
        createdAt: Date(timeIntervalSince1970: 100),
        url: "https://example.com/retry"
    )
    retry.result = .success
    retry.attemptCount = 2

    try repository.upsert(first)
    try repository.upsert(retry)

    let restored = try repository.recent(limit: 10, newerThan: .distantPast)
    #expect(restored.count == 1)
    #expect(restored[0].id == first.id)
    #expect(restored[0].requestID == requestID)
    #expect(restored[0].attemptCount == 2)
    #expect(restored[0].sanitizedURL?.absoluteString == "https://example.com/retry")
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

@Test @MainActor func historyRetentionKeepsStableLegacyIdentityButRepairsItWithLatestPayload() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let context = ModelContext(result.container)
    let requestID = fixedUUID(710)
    var oldFailure = historyEntry(
        id: fixedUUID(711),
        requestID: requestID,
        createdAt: Date(timeIntervalSince1970: 100),
        url: "https://example.com/old-failure"
    )
    oldFailure.result = .failure
    oldFailure.failureReason = "launch_failed"
    oldFailure.attemptCount = 1
    oldFailure.completedAt = Date(timeIntervalSince1970: 101)
    var latestSuccess = historyEntry(
        id: fixedUUID(712),
        requestID: requestID,
        createdAt: Date(timeIntervalSince1970: 100),
        url: "https://example.com/latest-success"
    )
    latestSuccess.attemptCount = 2
    latestSuccess.completedAt = Date(timeIntervalSince1970: 102)
    context.insert(HistoryRecord(entry: oldFailure))
    context.insert(HistoryRecord(entry: latestSuccess))
    try context.save()
    let repository = SwiftDataHistoryRepository(container: result.container)

    try repository.enforceRetention(limit: 100, cutoff: .distantPast)

    let restored = try repository.recent(limit: 10, newerThan: .distantPast)
    #expect(restored.count == 1)
    #expect(restored.first?.id == oldFailure.id)
    #expect(restored.first?.result == .success)
    #expect(restored.first?.attemptCount == 2)
    #expect(restored.first?.completedAt == latestSuccess.completedAt)
    #expect(restored.first?.sanitizedURL?.absoluteString == "https://example.com/latest-success")
}

@Test @MainActor func historyServiceEnforcesThirtyDaysAndOneHundredRowsBeforeEveryRead() async throws {
    let now = Date(timeIntervalSince1970: 10_000_000)
    let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
    let cutoffRepository = InMemoryHistoryRepository()
    try cutoffRepository.upsert(historyEntry(createdAt: cutoff.addingTimeInterval(-1), url: "https://expired.example"))
    let atCutoff = historyEntry(createdAt: cutoff, url: "https://cutoff.example")
    try cutoffRepository.upsert(atCutoff)
    let cutoffService = HistoryService(repository: cutoffRepository, now: { now })

    let cutoffRows = try await cutoffService.loadRecent(settings: .defaults)

    #expect(cutoffRows.map(\.id) == [atCutoff.id])

    let limitedRepository = InMemoryHistoryRepository()
    for offset in 0 ... 100 {
        try limitedRepository.upsert(historyEntry(
            requestID: fixedUUID(1_000 + offset),
            createdAt: now.addingTimeInterval(TimeInterval(-offset)),
            url: "https://limit.example/\(offset)"
        ))
    }
    let limitedService = HistoryService(repository: limitedRepository, now: { now })

    let limitedRows = try await limitedService.loadRecent(settings: .defaults)

    #expect(limitedRows.count == 100)
    #expect(limitedRows.first?.sanitizedURL?.absoluteString == "https://limit.example/0")
    #expect(limitedRows.last?.sanitizedURL?.absoluteString == "https://limit.example/99")
}

@Test @MainActor func historyServiceEnforcesRetentionAfterEveryUpsert() async throws {
    let now = Date(timeIntervalSince1970: 20_000_000)
    let repository = CountingHistoryRepository()
    let service = HistoryService(repository: repository, now: { now })

    try await service.upsert(
        historyEntry(createdAt: now, url: "https://example.com/new"),
        settings: .defaults
    )

    #expect(repository.upsertCount == 1)
    #expect(repository.retentionCalls == [
        .init(limit: 100, cutoff: now.addingTimeInterval(-30 * 24 * 60 * 60)),
    ])
}

@Test @MainActor func historyDeleteScrubsRecoveryJournalBeforeRemovingTheVisibleRow() async throws {
    let entry = historyEntry(requestID: fixedUUID(1_200), url: "https://example.com/private")
    let repository = CountingHistoryRepository(entries: [entry])
    let terminal = TerminalRequestRecord(
        requestID: entry.requestID,
        outcome: .cancelled,
        historyEntry: entry,
        completedAt: Date(timeIntervalSince1970: 10)
    )
    let store = HistoryFailurePendingStore(snapshot: .init(pendingRequests: [], terminalRecords: [terminal]))
    let queue = LinkRequestQueue(store: store)
    try await queue.restore()
    await store.failNextSave()
    let service = HistoryService(repository: repository)

    await #expect(throws: HistoryFailurePendingStore.Failure.self) {
        try await service.delete(entry: entry, queue: queue)
    }

    #expect(repository.deleteCount == 0)
    #expect(try repository.recent(limit: 10, newerThan: .distantPast) == [entry])
    #expect((await queue.terminalSnapshot()).first?.historyEntry == entry)
}

@Test @MainActor func historyClearUsesOneAtomicJournalScrubBeforeClearingTheRepository() async throws {
    let first = historyEntry(requestID: fixedUUID(1_201), url: "https://example.com/first")
    let second = historyEntry(requestID: fixedUUID(1_202), url: "https://example.com/second")
    let repository = CountingHistoryRepository(entries: [first, second])
    let terminals = [first, second].map { entry in
        TerminalRequestRecord(
            requestID: entry.requestID,
            outcome: .cancelled,
            historyEntry: entry,
            completedAt: Date(timeIntervalSince1970: 10)
        )
    }
    let store = HistoryFailurePendingStore(snapshot: .init(pendingRequests: [], terminalRecords: terminals))
    let queue = LinkRequestQueue(store: store)
    try await queue.restore()
    await store.failNextSave()
    let service = HistoryService(repository: repository)

    await #expect(throws: HistoryFailurePendingStore.Failure.self) {
        try await service.clear(queue: queue)
    }

    #expect(repository.clearCount == 0)
    #expect(try repository.recent(limit: 10, newerThan: .distantPast).count == 2)
    #expect((await queue.terminalSnapshot()).compactMap(\.historyEntry).count == 2)
}

@Test @MainActor func historyDeleteReportsRecoveryScrubWhenVisibleRowRemovalFails() async throws {
    let entry = historyEntry(requestID: fixedUUID(1_204), url: "https://example.com/private")
    let repository = CountingHistoryRepository(entries: [entry])
    repository.failDelete = true
    let terminal = TerminalRequestRecord(
        requestID: entry.requestID,
        outcome: .cancelled,
        historyEntry: entry,
        completedAt: Date(timeIntervalSince1970: 10)
    )
    let queue = LinkRequestQueue(store: HistoryFailurePendingStore(snapshot: .init(
        pendingRequests: [],
        terminalRecords: [terminal]
    )))
    try await queue.restore()
    let service = HistoryService(repository: repository)

    do {
        try await service.delete(entry: entry, queue: queue)
        Issue.record("Expected the History delete to report its partial scrub")
    } catch let error as HistoryServiceError {
        #expect(error == .recoveryPayloadScrubbedButHistoryDeleteFailed)
    }

    #expect(try repository.recent(limit: 10, newerThan: .distantPast) == [entry])
    #expect((await queue.terminalSnapshot()).first?.historyEntry == nil)
}

@Test @MainActor func historyClearReportsRecoveryScrubWhenVisibleRowsCannotBeCleared() async throws {
    let first = historyEntry(requestID: fixedUUID(1_205), url: "https://example.com/first")
    let second = historyEntry(requestID: fixedUUID(1_206), url: "https://example.com/second")
    let repository = CountingHistoryRepository(entries: [first, second])
    repository.failClear = true
    let terminalRecords = [first, second].map { entry in
        TerminalRequestRecord(
            requestID: entry.requestID,
            outcome: .cancelled,
            historyEntry: entry,
            completedAt: Date(timeIntervalSince1970: 10)
        )
    }
    let queue = LinkRequestQueue(store: HistoryFailurePendingStore(snapshot: .init(
        pendingRequests: [],
        terminalRecords: terminalRecords
    )))
    try await queue.restore()
    let service = HistoryService(repository: repository)

    do {
        try await service.clear(queue: queue)
        Issue.record("Expected the History clear to report its partial scrub")
    } catch let error as HistoryServiceError {
        #expect(error == .recoveryPayloadScrubbedButHistoryClearFailed)
    }

    #expect(try repository.recent(limit: 10, newerThan: .distantPast).count == 2)
    #expect((await queue.terminalSnapshot()).compactMap(\.historyEntry).isEmpty)
}

@Test @MainActor func queuedReconciliationReadsTerminalSnapshotOnlyAfterClearFinishes() async throws {
    let entry = historyEntry(requestID: fixedUUID(1_203), url: "https://example.com/do-not-revive")
    let terminal = TerminalRequestRecord(
        requestID: entry.requestID,
        outcome: .cancelled,
        historyEntry: entry,
        completedAt: Date(timeIntervalSince1970: 10)
    )
    let repository = CountingHistoryRepository(entries: [entry])
    let store = ScriptedPendingRequestStore(
        snapshot: .init(pendingRequests: [], terminalRecords: [terminal]),
        suspendedSaveCalls: [1]
    )
    let queue = LinkRequestQueue(store: store)
    try await queue.restore()
    let service = HistoryService(repository: repository)

    let clear = Task { @MainActor in try await service.clear(queue: queue) }
    await store.waitUntilSaveSuspended(call: 1)
    let reconcile = Task { @MainActor in
        await service.reconcile(queue: queue, settings: .defaults, warning: { _ in })
    }
    await Task.yield()
    await store.releaseSuspendedSave(call: 1)

    try await clear.value
    #expect(await reconcile.value)
    #expect(try repository.recent(limit: 10, newerThan: .distantPast).isEmpty)
    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(repository.upsertCount == 0)
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

@Test @MainActor func rulePriorityReorderIsCommittedTogetherOrNotAtAll() throws {
    let result = try ModelContainerFactory.make(inMemory: true)
    let repository = SwiftDataRuleRepository(container: result.container)
    let first = routingRule(id: fixedUUID(21), matcher: .exactHost("first.example"), priority: 0)
    let second = routingRule(id: fixedUUID(22), matcher: .exactHost("second.example"), priority: 1)
    try repository.upsert(first)
    try repository.upsert(second)

    var secondFirst = second
    secondFirst.priority = 0
    var firstSecond = first
    firstSecond.priority = 1
    try repository.updatePriorities([secondFirst, firstSecond])
    #expect(try repository.all() == [secondFirst, firstSecond])

    var rollbackCandidate = secondFirst
    rollbackCandidate.priority = 1
    let missing = routingRule(id: fixedUUID(23), matcher: .exactHost("missing.example"), priority: 0)
    do {
        try repository.updatePriorities([rollbackCandidate, missing])
        Issue.record("Expected a missing rule to fail the complete priority update")
    } catch let error as RuleRepositoryError {
        #expect(error == .missingRule(missing.id))
    }
    #expect(try repository.all() == [secondFirst, firstSecond])
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
    #expect(settings.loadCount == 1)
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

@Test @MainActor func reconciliationUsesAlwaysAskAndNoHistoryWhenSettingsCannotLoad() async throws {
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
    let terminal = try #require(await queue.terminalSnapshot().first)
    #expect(terminal.requestID == request.id)
    #expect(terminal.historyEntry == nil)
    #expect(try history.recent(limit: 10, newerThan: .distantPast).isEmpty)
}

@Test @MainActor func settingsFailureScrubsEveryTerminalHistoryFromTheFirstRecoverySave() async throws {
    let recovery = sensitiveRecoverySnapshot()
    let store = RecordingPendingRequestStore(snapshot: recovery.snapshot)
    let queue = LinkRequestQueue(store: store)
    let history = InMemoryHistoryRepository()
    let environment = makeEnvironment(
        unmatchedBehavior: .preferredBrowser,
        historyRepository: history,
        settingsRepository: FailingSettingsRepository()
    )

    let restored = await environment.restoreAndReconcile(queue: queue, warningSource: nil)

    #expect(restored)
    #expect(environment.unmatchedBehavior == .alwaysAsk)
    #expect(environment.persistenceWarnings == [.settingsNotSaved])
    #expect(try history.recent(limit: 10, newerThan: .distantPast).isEmpty)
    let pending = await queue.snapshot()
    #expect(pending.map(\.id) == recovery.pendingIDs)
    #expect(pending.map(\.state) == [.outcomeUnknown, .presenting, .outcomeUnknown])
    let terminal = await queue.terminalSnapshot()
    #expect(terminal.map(\.requestID) == recovery.terminalIDs)
    #expect(terminal.allSatisfy { $0.historyEntry == nil })
    let saves = await store.savedSnapshots
    #expect(!saves.isEmpty)
    #expect(saves.allSatisfy { snapshot in
        snapshot.terminalRecords.allSatisfy { $0.historyEntry == nil }
    })
}

@Test @MainActor func historyDisabledScrubsEveryTerminalHistoryBeforeCompactionSaves() async throws {
    let recovery = sensitiveRecoverySnapshot()
    let store = RecordingPendingRequestStore(snapshot: recovery.snapshot)
    let queue = LinkRequestQueue(store: store)
    let history = InMemoryHistoryRepository()
    var settings = AppSettings.defaults
    settings.historyEnabled = false
    let environment = makeEnvironment(
        historyRepository: history,
        settingsRepository: InMemorySettingsRepository(settings: settings)
    )

    let restored = await environment.restoreAndReconcile(queue: queue, warningSource: nil)

    #expect(restored)
    #expect(try history.recent(limit: 10, newerThan: .distantPast).isEmpty)
    #expect(await queue.snapshot().map(\.id) == recovery.pendingIDs)
    #expect(await queue.terminalSnapshot().isEmpty)
    let saves = await store.savedSnapshots
    #expect(!saves.isEmpty)
    #expect(saves.allSatisfy { snapshot in
        snapshot.terminalRecords.allSatisfy { $0.historyEntry == nil }
    })
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

@Test @MainActor func pendingTerminalHistoryRetrySucceedsWithoutClearingExistingWarnings() async throws {
    let request = LinkRequest.fixture()
    let entry = historyEntry(requestID: request.id, url: "https://example.com/retry")
    let store = InMemoryPendingRequestStore(snapshot: terminalSnapshot(request: request, entry: entry))
    let queue = LinkRequestQueue(store: store)
    let history = ScriptedHistoryRepository(failingRequestIDs: [request.id])
    let environment = makeEnvironment(historyRepository: history)
    environment.present(.settingsNotSaved)

    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))
    #expect(environment.hasPendingTerminalHistoryReconciliation)
    #expect(await queue.terminalSnapshot().map(\.requestID) == [request.id])

    history.failingRequestIDs = []
    #expect(await environment.retryPendingTerminalHistory(queue: queue))

    #expect(!environment.hasPendingTerminalHistoryReconciliation)
    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(history.persistedEntries.map(\.requestID) == [request.id])
    #expect(environment.persistenceWarnings.contains(.historyNotSaved))
    #expect(environment.persistenceWarnings.contains(.settingsNotSaved))
}

@Test @MainActor func pendingTerminalHistoryRetryKeepsStateWhenHistoryContinuesFailing() async throws {
    let request = LinkRequest.fixture()
    let entry = historyEntry(requestID: request.id, url: "https://example.com/still-failing")
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore(
        snapshot: terminalSnapshot(request: request, entry: entry)
    ))
    let history = ScriptedHistoryRepository(failingRequestIDs: [request.id])
    let settings = MutableSettingsRepository()
    let environment = makeEnvironment(
        historyRepository: history,
        settingsRepository: settings
    )

    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))
    #expect(!(await environment.retryPendingTerminalHistory(queue: queue)))

    #expect(environment.hasPendingTerminalHistoryReconciliation)
    #expect(await queue.terminalSnapshot().map(\.requestID) == [request.id])
    #expect(history.upsertAttempts == [request.id, request.id])
    #expect(settings.loadCount == 2)
}

@Test @MainActor func pendingTerminalHistoryRetryRepeatsIdempotentUpsertAfterCompactionFailure() async throws {
    let request = LinkRequest.fixture()
    let entry = historyEntry(requestID: request.id, url: "https://example.com/compact-retry")
    let store = ScriptedPendingRequestStore(
        snapshot: terminalSnapshot(request: request, entry: entry),
        failingSaveCalls: [1]
    )
    let queue = LinkRequestQueue(store: store)
    let history = ScriptedHistoryRepository()
    let environment = makeEnvironment(historyRepository: history)

    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))
    #expect(environment.hasPendingTerminalHistoryReconciliation)
    #expect(await queue.terminalSnapshot().map(\.requestID) == [request.id])
    #expect(history.upsertAttempts == [request.id])

    #expect(await environment.retryPendingTerminalHistory(queue: queue))

    #expect(!environment.hasPendingTerminalHistoryReconciliation)
    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(history.upsertAttempts == [request.id, request.id])
    #expect(history.persistedEntries.map(\.requestID) == [request.id])
    #expect(environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
}

@Test @MainActor func reconciliationCompactsSuccessfulTerminalsAndRetainsOnlyFailedTerminals() async throws {
    let first = LinkRequest.fixture(id: fixedUUID(921))
    let second = LinkRequest.fixture(id: fixedUUID(922))
    let firstEntry = historyEntry(requestID: first.id, url: "https://example.com/first")
    let secondEntry = historyEntry(requestID: second.id, url: "https://example.com/second")
    let snapshot = PendingRequestSnapshot(
        pendingRequests: [],
        terminalRecords: [
            terminalRecord(request: first, entry: firstEntry),
            terminalRecord(request: second, entry: secondEntry)
        ]
    )
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore(snapshot: snapshot))
    let history = ScriptedHistoryRepository(failingRequestIDs: [second.id])
    let environment = makeEnvironment(historyRepository: history)

    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))

    #expect(environment.hasPendingTerminalHistoryReconciliation)
    #expect(await queue.terminalSnapshot().map(\.requestID) == [second.id])
    #expect(history.persistedEntries.map(\.requestID) == [first.id])
    #expect(history.upsertAttempts == [first.id, second.id])
}

@Test @MainActor func retryReloadsHistoryDisabledSettingAndScrubsBeforeCompacting() async throws {
    let request = LinkRequest.fixture()
    let pending = LinkRequest.fixture(id: fixedUUID(931), url: "https://example.com/pending")
    let entry = historyEntry(requestID: request.id, url: "https://example.com/disable-history")
    let snapshot = PendingRequestSnapshot(
        pendingRequests: [pending],
        terminalRecords: [terminalRecord(request: request, entry: entry)]
    )
    let store = ScriptedPendingRequestStore(snapshot: snapshot)
    let queue = LinkRequestQueue(store: store)
    let history = ScriptedHistoryRepository(failingRequestIDs: [request.id])
    let settings = MutableSettingsRepository()
    let environment = makeEnvironment(
        historyRepository: history,
        settingsRepository: settings
    )

    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))
    settings.update { $0.historyEnabled = false }

    #expect(await environment.retryPendingTerminalHistory(queue: queue))

    #expect(!environment.hasPendingTerminalHistoryReconciliation)
    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(await queue.snapshot() == [pending])
    #expect(history.upsertAttempts == [request.id])
    let saves = await store.savedSnapshots
    #expect(saves.count == 2)
    #expect(saves[0].terminalRecords.first?.historyEntry == nil)
    #expect(saves[1].terminalRecords.isEmpty)
}

@Test @MainActor func retrySettingsLoadFailureDoesNotWriteHistoryOrCompactTerminal() async throws {
    let request = LinkRequest.fixture()
    let entry = historyEntry(requestID: request.id, url: "https://example.com/settings-failure")
    let store = ScriptedPendingRequestStore(snapshot: terminalSnapshot(request: request, entry: entry))
    let queue = LinkRequestQueue(store: store)
    let history = ScriptedHistoryRepository(failingRequestIDs: [request.id])
    let settings = MutableSettingsRepository()
    let environment = makeEnvironment(
        historyRepository: history,
        settingsRepository: settings
    )

    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))
    settings.shouldFailLoad = true
    let attemptsBeforeRetry = history.upsertAttempts

    #expect(!(await environment.retryPendingTerminalHistory(queue: queue)))

    #expect(environment.hasPendingTerminalHistoryReconciliation)
    #expect(await queue.terminalSnapshot().map(\.requestID) == [request.id])
    #expect(history.upsertAttempts == attemptsBeforeRetry)
    #expect(await store.saveCount == 0)
    #expect(settings.loadCount == 2)
    #expect(environment.persistenceWarnings.contains(.settingsNotSaved))
}

@Test @MainActor func concurrentPendingTerminalHistoryRetriesShareOneOperation() async throws {
    let request = LinkRequest.fixture()
    let entry = historyEntry(requestID: request.id, url: "https://example.com/single-flight")
    let store = ScriptedPendingRequestStore(
        snapshot: terminalSnapshot(request: request, entry: entry),
        suspendedSaveCalls: [1]
    )
    let queue = LinkRequestQueue(store: store)
    let history = ScriptedHistoryRepository(failingRequestIDs: [request.id])
    let settings = MutableSettingsRepository()
    let environment = makeEnvironment(
        historyRepository: history,
        settingsRepository: settings
    )

    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))
    history.failingRequestIDs = []

    let first = Task { @MainActor in
        await environment.retryPendingTerminalHistory(queue: queue)
    }
    await store.waitUntilSaveSuspended(call: 1)
    let second = Task { @MainActor in
        await environment.retryPendingTerminalHistory(queue: queue)
    }
    await Task.yield()

    #expect(settings.loadCount == 2)
    #expect(history.upsertAttempts == [request.id, request.id])

    await store.releaseSuspendedSave(call: 1)
    #expect(await first.value)
    #expect(await second.value)
    #expect(settings.loadCount == 2)
    #expect(history.upsertAttempts == [request.id, request.id])
    #expect(!environment.hasPendingTerminalHistoryReconciliation)
}

@Test @MainActor func retryLeavesOrdinaryPendingRequestsUnchanged() async throws {
    let terminalRequest = LinkRequest.fixture(id: fixedUUID(941))
    let pending = LinkRequest.fixture(
        id: fixedUUID(942),
        url: "https://example.com/ordinary-pending",
        state: .presenting
    )
    let entry = historyEntry(requestID: terminalRequest.id, url: "https://example.com/terminal")
    let snapshot = PendingRequestSnapshot(
        pendingRequests: [pending],
        terminalRecords: [terminalRecord(request: terminalRequest, entry: entry)]
    )
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore(snapshot: snapshot))
    let history = ScriptedHistoryRepository(failingRequestIDs: [terminalRequest.id])
    let environment = makeEnvironment(historyRepository: history)

    #expect(await environment.restoreAndReconcile(queue: queue, warningSource: nil))
    history.failingRequestIDs = []
    #expect(await environment.retryPendingTerminalHistory(queue: queue))

    #expect(await queue.snapshot() == [pending])
    #expect(await queue.terminalSnapshot().isEmpty)
}

@Test @MainActor func productionCompositionRetriesPendingTerminalHistoryOnItsSharedQueue() async throws {
    let request = LinkRequest.fixture()
    let entry = historyEntry(requestID: request.id, url: "https://example.com/composition-retry")
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore(
        snapshot: terminalSnapshot(request: request, entry: entry)
    ))
    let history = ScriptedHistoryRepository(failingRequestIDs: [request.id])
    let environment = makeEnvironment(historyRepository: history)
    let composition = ProductionAppComposition(
        environment: environment,
        recoveryQueue: queue,
        warningSource: nil
    )

    #expect(await composition.restoreOnce())
    #expect(environment.hasPendingTerminalHistoryReconciliation)
    history.failingRequestIDs = []

    #expect(await composition.retryPendingTerminalHistory())
    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(!environment.hasPendingTerminalHistoryReconciliation)
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

private func terminalRecord(
    request: LinkRequest,
    entry: HistoryEntry?
) -> TerminalRequestRecord {
    TerminalRequestRecord(
        requestID: request.id,
        outcome: .succeeded,
        historyEntry: entry,
        completedAt: Date(timeIntervalSince1970: 100)
    )
}

private func terminalSnapshot(
    request: LinkRequest,
    entry: HistoryEntry?
) -> PendingRequestSnapshot {
    PendingRequestSnapshot(
        pendingRequests: [],
        terminalRecords: [terminalRecord(request: request, entry: entry)]
    )
}

private func sensitiveRecoverySnapshot() -> (
    snapshot: PendingRequestSnapshot,
    pendingIDs: [UUID],
    terminalIDs: [UUID]
) {
    let launching = LinkRequest.fixture(
        id: fixedUUID(901),
        url: "https://example.com/launching?token=secret",
        state: .launching
    )
    let presenting = LinkRequest.fixture(
        id: fixedUUID(902),
        url: "https://example.com/presenting?token=secret",
        state: .presenting
    )
    let unknown = LinkRequest.fixture(
        id: fixedUUID(903),
        url: "https://example.com/unknown?token=secret",
        state: .outcomeUnknown
    )
    let firstTerminalID = fixedUUID(904)
    let secondTerminalID = fixedUUID(905)
    let terminalRecords = [
        TerminalRequestRecord(
            requestID: firstTerminalID,
            outcome: .succeeded,
            historyEntry: historyEntry(
                requestID: firstTerminalID,
                url: "https://example.com/first-private"
            ),
            completedAt: Date(timeIntervalSince1970: 10)
        ),
        TerminalRequestRecord(
            requestID: secondTerminalID,
            outcome: .cancelled,
            historyEntry: historyEntry(
                requestID: secondTerminalID,
                url: "https://example.com/second-private"
            ),
            completedAt: Date(timeIntervalSince1970: 11)
        )
    ]
    return (
        PendingRequestSnapshot(
            pendingRequests: [launching, presenting, unknown],
            terminalRecords: terminalRecords
        ),
        [launching.id, presenting.id, unknown.id],
        [firstTerminalID, secondTerminalID]
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
    func upsertAndEnforceRetention(_: HistoryEntry, limit _: Int, cutoff _: Date) throws {
        throw Failure.unavailable
    }
    func recent(limit _: Int, newerThan _: Date) throws -> [HistoryEntry] { [] }
    func delete(id _: UUID) throws {}
    func clear() throws {}
    func enforceRetention(limit _: Int, cutoff _: Date) throws {}
}

@MainActor
private final class CountingHistoryRepository: HistoryRepository {
    private enum Failure: Error { case expected }

    struct RetentionCall: Equatable {
        let limit: Int
        let cutoff: Date
    }

    private var entriesByRequestID: [UUID: HistoryEntry]
    private(set) var upsertCount = 0
    private(set) var deleteCount = 0
    private(set) var clearCount = 0
    private(set) var retentionCalls: [RetentionCall] = []
    var failDelete = false
    var failClear = false

    init(entries: [HistoryEntry] = []) {
        entriesByRequestID = Dictionary(uniqueKeysWithValues: entries.map { ($0.requestID, $0) })
    }

    func upsert(_ entry: HistoryEntry) throws {
        upsertCount += 1
        entriesByRequestID[entry.requestID] = entry
    }

    func upsertAndEnforceRetention(_ entry: HistoryEntry, limit: Int, cutoff: Date) throws {
        let previous = entriesByRequestID
        do {
            try upsert(entry)
            try enforceRetention(limit: limit, cutoff: cutoff)
        } catch {
            entriesByRequestID = previous
            throw error
        }
    }

    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry] {
        Array(entriesByRequestID.values
            .filter { $0.createdAt >= newerThan }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(max(limit, 0)))
    }

    func delete(id: UUID) throws {
        deleteCount += 1
        if failDelete { throw Failure.expected }
        guard let requestID = entriesByRequestID.first(where: { $0.value.id == id })?.key else { return }
        entriesByRequestID[requestID] = nil
    }

    func clear() throws {
        clearCount += 1
        if failClear { throw Failure.expected }
        entriesByRequestID.removeAll()
    }

    func enforceRetention(limit: Int, cutoff: Date) throws {
        retentionCalls.append(.init(limit: limit, cutoff: cutoff))
        entriesByRequestID = entriesByRequestID.filter { $0.value.createdAt >= cutoff }
        let retained = try recent(limit: limit, newerThan: .distantPast)
        entriesByRequestID = Dictionary(uniqueKeysWithValues: retained.map { ($0.requestID, $0) })
    }
}

private actor HistoryFailurePendingStore: PendingRequestStore {
    enum Failure: Error { case saveFailed }

    private var snapshot: PendingRequestSnapshot
    private var failedSavesRemaining = 0

    init(snapshot: PendingRequestSnapshot) {
        self.snapshot = snapshot
    }

    func load() async throws -> PendingRequestSnapshot { snapshot }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        if failedSavesRemaining > 0 {
            failedSavesRemaining -= 1
            throw Failure.saveFailed
        }
        self.snapshot = snapshot
    }

    func failNextSave() {
        failedSavesRemaining += 1
    }
}

@MainActor
private final class ScriptedHistoryRepository: HistoryRepository {
    private enum Failure: Error { case unavailable }

    var failingRequestIDs: Set<UUID>
    private(set) var upsertAttempts: [UUID] = []
    private(set) var persistedEntries: [HistoryEntry] = []

    init(failingRequestIDs: Set<UUID> = []) {
        self.failingRequestIDs = failingRequestIDs
    }

    func upsert(_ entry: HistoryEntry) throws {
        upsertAttempts.append(entry.requestID)
        guard !failingRequestIDs.contains(entry.requestID) else {
            throw Failure.unavailable
        }
        if let index = persistedEntries.firstIndex(where: { $0.id == entry.id }) {
            persistedEntries[index] = entry
        } else {
            persistedEntries.append(entry)
        }
    }

    func upsertAndEnforceRetention(_ entry: HistoryEntry, limit: Int, cutoff: Date) throws {
        let previous = persistedEntries
        do {
            try upsert(entry)
            try enforceRetention(limit: limit, cutoff: cutoff)
        } catch {
            persistedEntries = previous
            throw error
        }
    }

    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry] {
        Array(persistedEntries.filter { $0.createdAt >= newerThan }.prefix(max(limit, 0)))
    }

    func delete(id: UUID) throws {
        persistedEntries.removeAll { $0.id == id }
    }

    func clear() throws {
        persistedEntries.removeAll()
    }

    func enforceRetention(limit: Int, cutoff: Date) throws {
        persistedEntries = Array(
            persistedEntries
                .filter { $0.createdAt >= cutoff }
                .prefix(max(limit, 0))
        )
    }
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

private actor ScriptedPendingRequestStore: PendingRequestStore {
    private var snapshot: PendingRequestSnapshot
    private var failingSaveCalls: Set<Int>
    private var suspendedSaveCalls: Set<Int>
    private var activeSuspendedSaveCalls: Set<Int> = []
    private var suspendedSaveContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var suspendedSaveObservers: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var saveCount = 0
    private(set) var savedSnapshots: [PendingRequestSnapshot] = []

    init(
        snapshot: PendingRequestSnapshot,
        failingSaveCalls: Set<Int> = [],
        suspendedSaveCalls: Set<Int> = []
    ) {
        self.snapshot = snapshot
        self.failingSaveCalls = failingSaveCalls
        self.suspendedSaveCalls = suspendedSaveCalls
    }

    func load() async throws -> PendingRequestSnapshot {
        snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        saveCount += 1
        let call = saveCount
        if suspendedSaveCalls.remove(call) != nil {
            activeSuspendedSaveCalls.insert(call)
            let observers = suspendedSaveObservers.removeValue(forKey: call) ?? []
            observers.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                suspendedSaveContinuations[call] = continuation
            }
            activeSuspendedSaveCalls.remove(call)
        }
        guard failingSaveCalls.remove(call) == nil else {
            throw TestPersistenceFailure.unavailable
        }
        savedSnapshots.append(snapshot)
        self.snapshot = snapshot
    }

    func waitUntilSaveSuspended(call: Int) async {
        if activeSuspendedSaveCalls.contains(call) { return }
        await withCheckedContinuation { continuation in
            suspendedSaveObservers[call, default: []].append(continuation)
        }
    }

    func releaseSuspendedSave(call: Int) {
        suspendedSaveContinuations.removeValue(forKey: call)?.resume()
    }
}

private actor RecordingPendingRequestStore: PendingRequestStore {
    private var snapshot: PendingRequestSnapshot
    private(set) var savedSnapshots: [PendingRequestSnapshot] = []

    init(snapshot: PendingRequestSnapshot) {
        self.snapshot = snapshot
    }

    func load() async throws -> PendingRequestSnapshot {
        snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        savedSnapshots.append(snapshot)
        self.snapshot = snapshot
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
private final class MutableSettingsRepository: SettingsRepository {
    private(set) var settings: AppSettings
    var shouldFailLoad = false
    private(set) var loadCount = 0

    init(settings: AppSettings = .defaults) {
        self.settings = settings
    }

    func load() throws -> AppSettings {
        loadCount += 1
        guard !shouldFailLoad else {
            throw TestPersistenceFailure.unavailable
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        self.settings = settings
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
    }
}

@MainActor
private final class FailingSettingsRepository: SettingsRepository {
    func load() throws -> AppSettings {
        throw TestPersistenceFailure.unavailable
    }

    func save(_: AppSettings) throws {}
}
