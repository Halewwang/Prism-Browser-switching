import Foundation
import Testing
@_spi(Testing) @testable import PrismCore

@Test func pendingCountStreamPublishesOnlyCommittedCountChanges() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    var iterator = await queue.pendingCountUpdates().makeAsyncIterator()
    let request = request(id: .test(9), url: "https://example.com/live-count")

    #expect(await iterator.next() == 0)
    #expect(try await queue.enqueue(request))
    #expect(await iterator.next() == 1)
    try await queue.markCancelled(request.id, historyEntry: nil)
    #expect(await iterator.next() == 0)
}

@Test func suspendedSavePublishesOnlyAfterTheSnapshotCommits() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let recorder = PendingCountRecorder()
    let stream = await queue.pendingCountUpdates()
    let consumer = Task {
        for await count in stream {
            await recorder.record(count)
        }
    }
    await recorder.waitUntilValueCount(1)
    await store.suspendNextSave()

    let enqueue = Task {
        try await queue.enqueue(request(id: .test(905), url: "https://example.com/suspended"))
    }
    await store.waitUntilSaveSuspended()

    #expect(await recorder.snapshot() == [0])
    #expect(await queue.snapshot().isEmpty)

    await store.releaseSuspendedSave()
    #expect(try await enqueue.value)
    await recorder.waitUntilValueCount(2)
    #expect(await recorder.snapshot() == [0, 1])
    consumer.cancel()
    _ = await consumer.result
}

@Test func pendingCountStreamBuffersOnlyTheNewestValueForSlowConsumers() async throws {
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    var iterator = await queue.pendingCountUpdates().makeAsyncIterator()
    _ = await iterator.next()

    #expect(try await queue.enqueue(request(id: .test(901), url: "https://example.com/one")))
    #expect(try await queue.enqueue(request(id: .test(902), url: "https://example.com/two")))
    #expect(try await queue.enqueue(request(id: .test(903), url: "https://example.com/three")))

    #expect(await iterator.next() == 3)
}

@Test func failedSaveNeverPublishesAnUncommittedPendingCount() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let stream = await queue.pendingCountUpdates()
    let recorder = PendingCountRecorder()
    let consumer = Task {
        for await count in stream {
            await recorder.record(count)
        }
    }
    await recorder.waitUntilValueCount(1)
    #expect(await recorder.snapshot() == [0])
    await store.failNextSave()

    await expectStoreFailure {
        _ = try await queue.enqueue(request(id: .test(904), url: "https://example.com/fails"))
    }

    #expect(await queue.snapshot().isEmpty)
    #expect((await store.latestSnapshot).pendingRequests.isEmpty)
    #expect(await recorder.snapshot() == [0])
    consumer.cancel()
    _ = await consumer.result
}

@Test func cancellingConsumerRemovesPendingCountSubscriber() async {
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    let stream = await queue.pendingCountUpdates()
    let consumer = Task {
        for await _ in stream {}
    }

    await waitForPendingCountSubscriberCount(1, in: queue)
    consumer.cancel()
    _ = await consumer.result
    await waitForPendingCountSubscriberCount(0, in: queue)
    #expect(await queue.pendingCountSubscriberCountForTesting() == 0)
}

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

@Test func restoreAtomicallyScrubsEveryTerminalHistoryWhileRecoveringPendingStates() async throws {
    let launching = request(id: .test(201), url: "https://example.com/launching", state: .launching)
    let presenting = request(id: .test(202), url: "https://example.com/presenting", state: .presenting)
    let unknown = request(id: .test(203), url: "https://example.com/unknown", state: .outcomeUnknown)
    let firstTerminalID = UUID.test(204)
    let secondTerminalID = UUID.test(205)
    let firstTerminal = TerminalRequestRecord(
        requestID: firstTerminalID,
        outcome: .succeeded,
        historyEntry: history(requestID: firstTerminalID, sanitizedURL: "https://example.com/first"),
        completedAt: Date(timeIntervalSince1970: 2)
    )
    let secondTerminal = TerminalRequestRecord(
        requestID: secondTerminalID,
        outcome: .cancelled,
        historyEntry: history(requestID: secondTerminalID, sanitizedURL: "https://example.com/second"),
        completedAt: Date(timeIntervalSince1970: 3)
    )
    let store = InMemoryPendingRequestStore(
        seed: [launching, presenting, unknown],
        terminal: [firstTerminal, secondTerminal]
    )
    let queue = LinkRequestQueue(store: store)

    try await queue.restore(discardTerminalHistory: true)

    let pending = await queue.snapshot()
    #expect(pending.map(\.id) == [launching.id, presenting.id, unknown.id])
    #expect(pending.map(\.state) == [.outcomeUnknown, .presenting, .outcomeUnknown])
    let terminal = await queue.terminalSnapshot()
    #expect(terminal.map(\.requestID) == [firstTerminalID, secondTerminalID])
    #expect(terminal.allSatisfy { $0.historyEntry == nil })
    #expect((await store.latestSnapshot).terminalRecords.allSatisfy { $0.historyEntry == nil })
    #expect(await store.saveCount == 1)
}

@Test func failedAtomicRestoreScrubDoesNotCommitPartialQueueMemory() async throws {
    let launching = request(id: .test(206), url: "https://example.com/launching", state: .launching)
    let terminalID = UUID.test(207)
    let terminal = TerminalRequestRecord(
        requestID: terminalID,
        outcome: .succeeded,
        historyEntry: history(requestID: terminalID, sanitizedURL: "https://example.com/private"),
        completedAt: Date(timeIntervalSince1970: 2)
    )
    let store = InMemoryPendingRequestStore(seed: [launching], terminal: [terminal])
    let queue = LinkRequestQueue(store: store)
    await store.failNextSave()

    await expectStoreFailure {
        try await queue.restore(discardTerminalHistory: true)
    }

    #expect(await queue.snapshot().isEmpty)
    #expect(await queue.terminalSnapshot().isEmpty)
    #expect((await store.latestSnapshot).pendingRequests == [launching])
    #expect((await store.latestSnapshot).terminalRecords == [terminal])
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
    #expect(!(try await queue.enqueue(first)))
}

@Test func discardingTerminalHistoryRetainsURLFreeOutcomeWithoutHistoryPayload() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let request = request(id: .test(13), url: "https://example.com/private?token=secret")
    let history = HistoryEntry.processing(
        request: request,
        sanitizedURL: URL(string: "https://example.com/private")
    )
    try await queue.enqueue(request)
    try await queue.markCompleted(request.id, historyEntry: history)

    try await queue.discardTerminalHistory(request.id)

    let terminal = try #require(await queue.terminalSnapshot().first)
    #expect(terminal.requestID == request.id)
    #expect(terminal.outcome == .succeeded)
    #expect(terminal.historyEntry == nil)
    #expect(await queue.next() == nil)
    #expect(await store.latestSnapshot == PendingRequestSnapshot(
        pendingRequests: [],
        terminalRecords: [terminal]
    ))
}

@Test func repeatedRestoreRetainsSeenIDsAfterTerminalCompaction() async throws {
    let first = request(id: .test(32), url: "https://example.com/first")
    let store = InMemoryPendingRequestStore(seed: [first])
    let queue = LinkRequestQueue(store: store)
    try await queue.restore()
    try await queue.markCompleted(first.id, historyEntry: nil)
    try await queue.compactTerminal(first.id)

    try await queue.restore()

    #expect(await queue.snapshot().isEmpty)
    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(!(try await queue.enqueue(first)))
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

@Test func automaticLaunchFromQueuedPersistsOnceAndRollsBackOnSaveFailure() async throws {
    let automatic = request(id: .test(61), url: "https://example.com/automatic")
    let rollback = request(id: .test(62), url: "https://example.com/rollback")
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    _ = try await queue.enqueue(automatic)
    _ = try await queue.enqueue(rollback)

    try await queue.markLaunching(automatic.id, browserID: "com.apple.Safari")

    let launched = try #require(await queue.snapshot().first)
    #expect(launched.state == .launching)
    #expect(launched.attemptCount == 1)
    #expect(launched.lastAttemptedBrowserID == "com.apple.Safari")
    #expect((await store.latestSnapshot).pendingRequests.first == launched)

    await expectQueueError(.illegalTransition(id: automatic.id, from: .launching, to: .launching)) {
        try await queue.markLaunching(automatic.id, browserID: "com.google.Chrome")
    }
    await store.failNextSave()
    await expectStoreFailure { try await queue.markLaunching(rollback.id, browserID: "com.apple.Safari") }

    #expect(await queue.snapshot() == [launched, rollback])
    #expect((await store.latestSnapshot).pendingRequests == [launched, rollback])
}

@Test func handoffFailureCanReturnLaunchingRequestToPresentingWithoutLosingContext() async throws {
    let original = request(id: .test(63), url: "https://example.com/handoff")
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    _ = try await queue.enqueue(original)
    try await queue.markLaunching(original.id, browserID: "com.apple.Safari")

    try await queue.markPresenting(original.id)

    let recovered = try #require(await queue.snapshot().first)
    #expect(recovered.state == .presenting)
    #expect(recovered.url == original.url)
    #expect(recovered.attemptCount == 1)
    #expect(recovered.lastAttemptedBrowserID == "com.apple.Safari")
    #expect(await queue.snapshot().map(\.id) == [original.id])
    #expect((await store.latestSnapshot).pendingRequests == [recovered])
    await expectQueueError(.illegalTransition(id: original.id, from: .presenting, to: .presenting)) {
        try await queue.markPresenting(original.id)
    }
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

@Test func restoreRejectsTerminalHistoryMismatchesWithoutChangingCommittedQueue() async throws {
    let known = request(id: .test(92), url: "https://example.com/known")
    let terminalID = UUID.test(93)
    let mismatchedHistoryID = UUID.test(94)
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    _ = try await queue.enqueue(known)
    let saveCountBefore = await store.saveCount
    await store.replaceLoadedSnapshot(PendingRequestSnapshot(
        pendingRequests: [],
        terminalRecords: [TerminalRequestRecord(
            requestID: terminalID,
            outcome: .succeeded,
            historyEntry: history(requestID: mismatchedHistoryID, sanitizedURL: "https://example.com/safe"),
            completedAt: Date(timeIntervalSince1970: 2)
        )]
    ))

    await expectQueueError(.mismatchedHistoryRequestID(expected: terminalID, actual: mismatchedHistoryID)) {
        try await queue.restore()
    }

    #expect(await queue.snapshot() == [known])
    #expect(await queue.terminalSnapshot().isEmpty)
    #expect(!(try await queue.enqueue(known)))
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
    await expectQueueError(.illegalTransition(id: original.id, from: .queued, to: .outcomeUnknown)) {
        try await queue.markOutcomeUnknown(original.id)
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

@Test func serializesConcurrentEnqueuesWithoutLosingTheFirstRequest() async throws {
    let first = request(id: .test(130), url: "https://example.com/first")
    let second = request(id: .test(131), url: "https://example.com/second")
    let store = InMemoryPendingRequestStore()
    let (waiterEvents, waiterSignal) = AsyncStream<Void>.makeStream()
    let queue = LinkRequestQueue(store: store, mutationWaiterObserver: {
        _ = waiterSignal.yield()
    })
    var waiterIterator = waiterEvents.makeAsyncIterator()
    await store.suspendNextSave()

    let firstEnqueue = Task { try await queue.enqueue(first) }
    await store.waitUntilSaveSuspended()
    let secondEnqueue = Task { try await queue.enqueue(second) }
    #expect(await waiterIterator.next() != nil)

    #expect(await store.saveCount == 1)

    await store.releaseSuspendedSave()
    #expect(try await firstEnqueue.value)
    #expect(try await secondEnqueue.value)
    let expected = PendingRequestSnapshot(pendingRequests: [first, second], terminalRecords: [])
    #expect(await queue.snapshot() == [first, second])
    #expect(await store.latestSnapshot == expected)
}

@Test func explicitEnqueueRefusesAnAlreadyPendingRequestWithoutSaving() async throws {
    let real = request(id: .test(132), url: "https://example.com/real")
    let synthetic = request(id: .test(133), url: "https://example.com/synthetic")
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    #expect(try await queue.enqueue(real))
    let saveCount = await store.saveCount

    #expect(!(try await queue.enqueueIfNoPending(synthetic)))

    #expect(await queue.snapshot() == [real])
    #expect(await store.saveCount == saveCount)
}

@Test func explicitEnqueueCannotOvertakeARealEnqueueSuspendedInPersistence() async throws {
    let real = request(id: .test(134), url: "https://example.com/real")
    let synthetic = request(id: .test(135), url: "https://example.com/synthetic")
    let store = InMemoryPendingRequestStore()
    let (waiterEvents, waiterSignal) = AsyncStream<Void>.makeStream()
    let queue = LinkRequestQueue(store: store, mutationWaiterObserver: {
        _ = waiterSignal.yield()
    })
    var waiterIterator = waiterEvents.makeAsyncIterator()
    await store.suspendNextSave()

    let realEnqueue = Task { try await queue.enqueue(real) }
    await store.waitUntilSaveSuspended()
    let syntheticEnqueue = Task { try await queue.enqueueIfNoPending(synthetic) }
    #expect(await waiterIterator.next() != nil)

    await store.releaseSuspendedSave()

    #expect(try await realEnqueue.value)
    #expect(!(try await syntheticEnqueue.value))
    #expect(await queue.snapshot() == [real])
    #expect(await store.latestSnapshot == PendingRequestSnapshot(
        pendingRequests: [real],
        terminalRecords: []
    ))
}

@Test func failedSerializedSaveReleasesTheNextQueuedMutation() async throws {
    let failed = request(id: .test(140), url: "https://example.com/failed")
    let succeeding = request(id: .test(141), url: "https://example.com/succeeding")
    let store = InMemoryPendingRequestStore()
    let (waiterEvents, waiterSignal) = AsyncStream<Void>.makeStream()
    let queue = LinkRequestQueue(store: store, mutationWaiterObserver: {
        _ = waiterSignal.yield()
    })
    var waiterIterator = waiterEvents.makeAsyncIterator()
    await store.suspendNextSave()
    await store.failNextSave()

    let failedEnqueue = Task { try await queue.enqueue(failed) }
    await store.waitUntilSaveSuspended()
    let succeedingEnqueue = Task { try await queue.enqueue(succeeding) }
    #expect(await waiterIterator.next() != nil)
    #expect(await store.saveCount == 1)

    await store.releaseSuspendedSave()
    await expectStoreFailure { _ = try await failedEnqueue.value }
    #expect(try await succeedingEnqueue.value)
    #expect(await queue.snapshot() == [succeeding])
    #expect((await store.latestSnapshot).pendingRequests == [succeeding])
}

private actor InMemoryPendingRequestStore: PendingRequestStore {
    enum StoreError: Error, Equatable {
        case saveFailed
    }

    private var storedSnapshot: PendingRequestSnapshot
    private(set) var latestSnapshot: PendingRequestSnapshot
    private(set) var saveCount = 0
    private var failedSavesRemaining = 0
    private var shouldSuspendNextSave = false
    private var suspendedSaveContinuations: [CheckedContinuation<Void, Never>] = []
    private var suspendedSaveObservers: [CheckedContinuation<Void, Never>] = []
    private var suspendedSaveCount = 0

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
        if shouldSuspendNextSave {
            shouldSuspendNextSave = false
            suspendedSaveCount += 1
            let observers = suspendedSaveObservers
            suspendedSaveObservers.removeAll()
            observers.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                suspendedSaveContinuations.append(continuation)
            }
            suspendedSaveCount -= 1
        }
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

    func suspendNextSave() {
        shouldSuspendNextSave = true
    }

    func waitUntilSaveSuspended() async {
        if suspendedSaveCount > 0 { return }
        await withCheckedContinuation { continuation in
            suspendedSaveObservers.append(continuation)
        }
    }

    func releaseSuspendedSave() {
        let continuation = suspendedSaveContinuations.removeFirst()
        continuation.resume()
    }

    func replaceLoadedSnapshot(_ snapshot: PendingRequestSnapshot) {
        storedSnapshot = snapshot
    }
}

private actor PendingCountRecorder {
    private var values: [Int] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func record(_ value: Int) {
        values.append(value)
        let ready = waiters.filter { values.count >= $0.count }
        waiters.removeAll { values.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }

    func snapshot() -> [Int] {
        values
    }

    func waitUntilValueCount(_ count: Int) async {
        if values.count >= count { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }
}

private func waitForPendingCountSubscriberCount(
    _ expected: Int,
    in queue: LinkRequestQueue,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0 ..< 1_000 {
        if await queue.pendingCountSubscriberCountForTesting() == expected { return }
        await Task.yield()
    }
    Issue.record(
        "Timed out waiting for pending count subscriber count \(expected)",
        sourceLocation: sourceLocation
    )
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
