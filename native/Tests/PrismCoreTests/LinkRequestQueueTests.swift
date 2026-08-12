import Foundation
import Testing
@testable import PrismCore

@Test func queuePreservesOrderAndRejectsDuplicateID() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let first = request(id: .test(10), url: "https://example.com/first")
    let second = request(id: .test(11), url: "https://example.com/second")

    #expect(try await queue.enqueue(first))
    #expect(try await queue.enqueue(second))
    #expect(!(try await queue.enqueue(first)))
    #expect(await queue.next() == first)

    try await queue.markCompleted(first.id, historyEntry: nil)

    #expect(await queue.next() == second)
    #expect(await queue.snapshot() == [second])
}

@Test func restoreNeverAutomaticallyReplaysAnInterruptedLaunch() async throws {
    let launching = LinkRequest(
        id: .test(20),
        url: URL(string: "https://example.com/interrupted")!,
        receivedAt: Date(timeIntervalSince1970: 1),
        source: .unknown,
        state: .launching,
        attemptCount: 1,
        lastAttemptedBrowserID: "com.apple.Safari"
    )
    let store = InMemoryPendingRequestStore(seed: [launching])
    let queue = LinkRequestQueue(store: store)

    try await queue.restore()

    let restored = try #require(await queue.snapshot().first)
    #expect(restored.state == .outcomeUnknown)
    #expect(await queue.next()?.id == launching.id)
    #expect((await store.latestSnapshot).pendingRequests.first?.state == .outcomeUnknown)
}

@Test func restoreContinuesWithFirstUnfinishedRequest() async throws {
    let first = request(id: .test(21), url: "https://example.com/first")
    let second = request(id: .test(22), url: "https://example.com/second", state: .presenting)
    let store = InMemoryPendingRequestStore(seed: [first, second])
    let queue = LinkRequestQueue(store: store)

    try await queue.restore()

    #expect(await queue.snapshot() == [first, second])
    #expect(await queue.next()?.id == first.id)
    #expect(await store.saveCount == 0)
}

@Test func terminalJournalDoesNotBlockNextAndSurvivesUntilCompacted() async throws {
    let first = request(id: .test(30), url: "https://example.com/first")
    let second = request(id: .test(31), url: "https://example.com/second")
    let history = history(requestID: first.id, sanitizedURL: "https://example.com/safe")
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    _ = try await queue.enqueue(first)
    _ = try await queue.enqueue(second)

    try await queue.markCompleted(first.id, historyEntry: history)

    let terminal = try #require(await queue.terminalSnapshot().first)
    #expect(await queue.next()?.id == second.id)
    #expect(terminal.requestID == first.id)
    #expect(terminal.outcome == .succeeded)
    #expect(terminal.historyEntry?.sanitizedURL == history.sanitizedURL)
    #expect(terminal.completedAt >= first.receivedAt)
    #expect(!(try await queue.enqueue(first)))

    try await queue.compactTerminal(first.id)

    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(await queue.snapshot() == [second])
    #expect(try await queue.enqueue(first))
}

@Test func identicalURLsWithDistinctIDsRemainSeparateFIFORequests() async throws {
    let first = request(id: .test(40), url: "https://example.com/shared")
    let second = request(id: .test(41), url: "https://example.com/shared")
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())

    #expect(try await queue.enqueue(first))
    #expect(try await queue.enqueue(second))

    #expect(await queue.snapshot() == [first, second])
}

@Test func nextSkipsLaunchingRequestsWithoutReordering() async throws {
    let launching = request(id: .test(50), url: "https://example.com/launching", state: .launching)
    let queued = request(id: .test(51), url: "https://example.com/queued")
    let unknown = request(id: .test(52), url: "https://example.com/unknown", state: .outcomeUnknown)
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    _ = try await queue.enqueue(launching)
    _ = try await queue.enqueue(queued)
    _ = try await queue.enqueue(unknown)

    #expect(await queue.next()?.id == queued.id)
    #expect(await queue.snapshot() == [launching, queued, unknown])
}

@Test func stateMutationsTrackOneLaunchAttemptAndPreserveMetadataOnUnknownOutcome() async throws {
    let original = request(id: .test(60), url: "https://example.com/state")
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    _ = try await queue.enqueue(original)

    try await queue.markPresenting(original.id)
    try await queue.markLaunching(original.id, browserID: "com.apple.Safari")

    let launching = try #require(await queue.snapshot().first)
    #expect(launching.state == .launching)
    #expect(launching.attemptCount == 1)
    #expect(launching.lastAttemptedBrowserID == "com.apple.Safari")

    await expectQueueError(.illegalTransition(id: original.id, from: .launching, to: .launching)) {
        try await queue.markLaunching(original.id, browserID: "com.google.Chrome")
    }
    try await queue.markOutcomeUnknown(original.id)

    let unknown = try #require(await queue.snapshot().first)
    #expect(unknown.state == .outcomeUnknown)
    #expect(unknown.attemptCount == 1)
    #expect(unknown.lastAttemptedBrowserID == "com.apple.Safari")
}

@Test func cancellationCreatesTerminalRecordAndRejectsMismatchedHistory() async throws {
    let original = request(id: .test(70), url: "https://example.com/cancel")
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    _ = try await queue.enqueue(original)
    let saveCountBeforeMismatch = await store.saveCount

    await expectQueueError(.mismatchedHistoryRequestID(expected: original.id, actual: .test(71))) {
        try await queue.markCancelled(original.id, historyEntry: history(requestID: .test(71), sanitizedURL: nil))
    }
    #expect(await queue.snapshot() == [original])
    #expect(await store.saveCount == saveCountBeforeMismatch)

    try await queue.markCancelled(original.id, historyEntry: history(requestID: original.id, sanitizedURL: nil))

    #expect(await queue.snapshot().isEmpty)
    #expect(await queue.terminalSnapshot().map(\.outcome) == [.cancelled])
}

@Test func restoreConvertsEveryInterruptedLaunchAndPersistsTheRecoveredSnapshot() async throws {
    let first = request(id: .test(80), url: "https://example.com/one", state: .launching)
    let second = request(id: .test(81), url: "https://example.com/two", state: .launching)
    let queued = request(id: .test(82), url: "https://example.com/three")
    let store = InMemoryPendingRequestStore(seed: [first, second, queued])
    let queue = LinkRequestQueue(store: store)

    try await queue.restore()

    #expect(await queue.snapshot().map(\.state) == [.outcomeUnknown, .outcomeUnknown, .queued])
    #expect(await store.latestSnapshot == PendingRequestSnapshot(
        pendingRequests: await queue.snapshot(),
        terminalRecords: []
    ))
    #expect(await store.saveCount == 1)
}

@Test func restoreRejectsDuplicateIDsAcrossPendingAndTerminalWithoutChangingMemory() async throws {
    let existing = request(id: .test(90), url: "https://example.com/existing")
    let duplicateID = UUID.test(91)
    let store = InMemoryPendingRequestStore(seed: [existing])
    let queue = LinkRequestQueue(store: store)
    try await queue.restore()
    await store.replaceLoadedSnapshot(PendingRequestSnapshot(
        pendingRequests: [request(id: duplicateID, url: "https://example.com/pending")],
        terminalRecords: [TerminalRequestRecord(requestID: duplicateID, outcome: .cancelled, historyEntry: nil, completedAt: Date())]
    ))
    let saveCountBefore = await store.saveCount

    await expectQueueError(.duplicateRequestID(duplicateID)) {
        try await queue.restore()
    }

    #expect(await queue.snapshot() == [existing])
    #expect(await store.saveCount == saveCountBefore)
}

@Test func unknownIDsAndIllegalTransitionsLeaveStateUntouchedWithoutSaving() async throws {
    let original = request(id: .test(100), url: "https://example.com/unknown")
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    _ = try await queue.enqueue(original)
    let saveCount = await store.saveCount

    await expectQueueError(.requestNotFound(.test(101))) {
        try await queue.markPresenting(.test(101))
    }
    await expectQueueError(.illegalTransition(id: original.id, from: .queued, to: .launching)) {
        try await queue.markLaunching(original.id, browserID: "com.apple.Safari")
    }
    await expectQueueError(.terminalRecordNotFound(.test(101))) {
        try await queue.compactTerminal(.test(101))
    }

    #expect(await queue.snapshot() == [original])
    #expect(await store.saveCount == saveCount)
}

@Test func failedSavesNeverCommitEnqueuePresentationLaunchOrUnknownOutcome() async throws {
    let original = request(id: .test(110), url: "https://example.com/failure")
    let added = request(id: .test(111), url: "https://example.com/added")
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)

    await store.failNextSave()
    await expectStoreFailure { try await queue.enqueue(added) }
    #expect(await queue.snapshot().isEmpty)
    #expect((await store.latestSnapshot).pendingRequests.isEmpty)

    _ = try await queue.enqueue(original)
    await store.failNextSave()
    await expectStoreFailure { try await queue.markPresenting(original.id) }
    #expect(await queue.snapshot() == [original])

    try await queue.markPresenting(original.id)
    let presenting = try #require(await queue.snapshot().first)
    await store.failNextSave()
    await expectStoreFailure { try await queue.markLaunching(original.id, browserID: "com.apple.Safari") }
    #expect(await queue.snapshot() == [presenting])

    try await queue.markLaunching(original.id, browserID: "com.apple.Safari")
    let launching = try #require(await queue.snapshot().first)
    await store.failNextSave()
    await expectStoreFailure { try await queue.markOutcomeUnknown(original.id) }
    #expect(await queue.snapshot() == [launching])
}

@Test func failedSavesNeverCommitTerminalOrCompactionAndRestoreRecoveryRollsBack() async throws {
    let original = request(id: .test(120), url: "https://example.com/terminal")
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    _ = try await queue.enqueue(original)

    await store.failNextSave()
    await expectStoreFailure { try await queue.markCompleted(original.id, historyEntry: nil) }
    #expect(await queue.snapshot() == [original])
    #expect(await queue.terminalSnapshot().isEmpty)

    await store.failNextSave()
    await expectStoreFailure { try await queue.markCancelled(original.id, historyEntry: nil) }
    #expect(await queue.snapshot() == [original])
    #expect(await queue.terminalSnapshot().isEmpty)

    try await queue.markCancelled(original.id, historyEntry: nil)
    let terminal = try #require(await queue.terminalSnapshot().first)
    await store.failNextSave()
    await expectStoreFailure { try await queue.compactTerminal(terminal.requestID) }
    #expect(await queue.terminalSnapshot() == [terminal])

    let launching = request(id: .test(121), url: "https://example.com/recovery", state: .launching)
    let recoveryStore = InMemoryPendingRequestStore(seed: [launching])
    let recoveryQueue = LinkRequestQueue(store: recoveryStore)
    await recoveryStore.failNextSave()
    await expectStoreFailure { try await recoveryQueue.restore() }
    #expect(await recoveryQueue.snapshot().isEmpty)
    #expect((await recoveryStore.latestSnapshot).pendingRequests == [launching])
}

private actor InMemoryPendingRequestStore: PendingRequestStore {
    enum StoreError: Error, Equatable {
        case saveFailed
    }

    private var storedSnapshot: PendingRequestSnapshot
    private(set) var latestSnapshot: PendingRequestSnapshot
    private(set) var saveCount = 0
    private var failedSavesRemaining = 0

    init(seed: [LinkRequest] = [], terminal: [TerminalRequestRecord] = []) {
        let snapshot = PendingRequestSnapshot(pendingRequests: seed, terminalRecords: terminal)
        storedSnapshot = snapshot
        latestSnapshot = snapshot
    }

    func load() async throws -> PendingRequestSnapshot {
        storedSnapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        saveCount += 1
        if failedSavesRemaining > 0 {
            failedSavesRemaining -= 1
            throw StoreError.saveFailed
        }
        storedSnapshot = snapshot
        latestSnapshot = snapshot
    }

    func failNextSave() {
        failedSavesRemaining += 1
    }

    func replaceLoadedSnapshot(_ snapshot: PendingRequestSnapshot) {
        storedSnapshot = snapshot
    }
}

private func request(id: UUID, url: String, state: LinkRequestState = .queued) -> LinkRequest {
    LinkRequest(
        id: id,
        url: URL(string: url)!,
        receivedAt: Date(timeIntervalSince1970: 1),
        source: .unknown,
        state: state
    )
}

private func history(requestID: UUID, sanitizedURL: String?) -> HistoryEntry {
    HistoryEntry(
        id: .test(999),
        requestID: requestID,
        sanitizedURL: sanitizedURL.flatMap(URL.init(string:)),
        sourceBundleIdentifier: nil,
        sourceDisplayName: "Unknown",
        targetBrowserID: nil,
        targetDisplayName: nil,
        method: nil,
        result: .success,
        matchingRuleID: nil,
        failureReason: nil,
        attemptCount: 1,
        createdAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2)
    )
}

private func expectQueueError(
    _ expected: LinkRequestQueueError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected queue error: \(expected)")
    } catch let actual as LinkRequestQueueError {
        #expect(actual == expected)
    } catch {
        Issue.record("Expected queue error \(expected), received \(error)")
    }
}

private func expectStoreFailure(operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected store save failure")
    } catch let actual as InMemoryPendingRequestStore.StoreError {
        #expect(actual == .saveFailed)
    } catch {
        Issue.record("Expected store save failure, received \(error)")
    }
}
