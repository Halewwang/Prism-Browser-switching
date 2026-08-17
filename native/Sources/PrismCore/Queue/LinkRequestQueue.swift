import Foundation

public enum LinkRequestQueueError: Error, Equatable, Sendable {
    case requestNotFound(UUID)
    case terminalRecordNotFound(UUID)
    case duplicateRequestID(UUID)
    case illegalTransition(id: UUID, from: LinkRequestState, to: LinkRequestState)
    case mismatchedHistoryRequestID(expected: UUID, actual: UUID)
}

public actor LinkRequestQueue {
    private let store: any PendingRequestStore
    private var pendingRequests: [LinkRequest] = []
    private var terminalRecords: [TerminalRequestRecord] = []
    private var requestIDs: Set<UUID> = []
    private var pendingCountContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]
    private var mutationPermitHeld = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    private let mutationWaiterObserver: (@Sendable () -> Void)?

    public init(store: any PendingRequestStore) {
        self.store = store
        mutationWaiterObserver = nil
    }

    init(store: any PendingRequestStore, mutationWaiterObserver: @escaping @Sendable () -> Void) {
        self.store = store
        self.mutationWaiterObserver = mutationWaiterObserver
    }

    public func restore(discardTerminalHistory: Bool = false) async throws {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        let loaded = try await store.load()
        try Self.validateSnapshot(in: loaded)

        var recovered = loaded
        var requiresSave = false
        let hasInterruptedLaunch = recovered.pendingRequests.contains { $0.state == .launching }
        if hasInterruptedLaunch {
            for index in recovered.pendingRequests.indices where recovered.pendingRequests[index].state == .launching {
                recovered.pendingRequests[index].state = .outcomeUnknown
            }
            requiresSave = true
        }
        if discardTerminalHistory,
           recovered.terminalRecords.contains(where: { $0.historyEntry != nil }) {
            recovered.terminalRecords = recovered.terminalRecords.map { record in
                TerminalRequestRecord(
                    requestID: record.requestID,
                    outcome: record.outcome,
                    historyEntry: nil,
                    completedAt: record.completedAt
                )
            }
            requiresSave = true
        }
        if requiresSave {
            try await store.save(recovered)
        }

        let previousPendingCount = pendingRequests.count
        pendingRequests = recovered.pendingRequests
        terminalRecords = recovered.terminalRecords
        requestIDs.formUnion(Self.requestIDs(in: recovered))
        publishPendingCountIfChanged(from: previousPendingCount)
    }

    public func pendingCountUpdates() -> AsyncStream<Int> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Int>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        pendingCountContinuations[id] = continuation
        if case .terminated = continuation.yield(pendingRequests.count) {
            pendingCountContinuations[id] = nil
        }
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removePendingCountContinuation(id: id)
            }
        }
        return stream
    }

    @_spi(Testing)
    public func pendingCountSubscriberCountForTesting() -> Int {
        pendingCountContinuations.count
    }

    @discardableResult
    public func enqueue(_ request: LinkRequest) async throws -> Bool {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        guard !requestIDs.contains(request.id) else { return false }

        let candidatePending = pendingRequests + [request]
        try await save(pending: candidatePending, terminal: terminalRecords)
        let previousPendingCount = pendingRequests.count
        pendingRequests = candidatePending
        requestIDs.insert(request.id)
        publishPendingCountIfChanged(from: previousPendingCount)
        return true
    }

    /// Enqueues only when no request is currently pending. The empty check and
    /// durable insert share the queue's mutation permit, so another enqueue
    /// cannot be overtaken between them.
    @discardableResult
    public func enqueueIfNoPending(_ request: LinkRequest) async throws -> Bool {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        guard pendingRequests.isEmpty, !requestIDs.contains(request.id) else {
            return false
        }

        let candidatePending = [request]
        try await save(pending: candidatePending, terminal: terminalRecords)
        let previousPendingCount = pendingRequests.count
        pendingRequests = candidatePending
        requestIDs.insert(request.id)
        publishPendingCountIfChanged(from: previousPendingCount)
        return true
    }

    public func next() -> LinkRequest? {
        pendingRequests.first { request in
            switch request.state {
            case .queued, .presenting, .outcomeUnknown:
                true
            case .launching:
                false
            }
        }
    }

    public func snapshot() -> [LinkRequest] {
        pendingRequests
    }

    public func terminalSnapshot() -> [TerminalRequestRecord] {
        terminalRecords
    }

    public func markPresenting(_ id: UUID) async throws {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        try await mutateRequest(id) { request in
            guard request.state == .queued || request.state == .launching || request.state == .outcomeUnknown else {
                throw LinkRequestQueueError.illegalTransition(id: id, from: request.state, to: .presenting)
            }
            request.state = .presenting
        }
    }

    public func markLaunching(_ id: UUID, browserID: BrowserID) async throws {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        try await mutateRequest(id) { request in
            guard request.state == .queued || request.state == .presenting || request.state == .outcomeUnknown else {
                throw LinkRequestQueueError.illegalTransition(id: id, from: request.state, to: .launching)
            }
            request.state = .launching
            request.lastAttemptedBrowserID = browserID
            request.attemptCount += 1
        }
    }

    public func markOutcomeUnknown(_ id: UUID) async throws {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        try await mutateRequest(id) { request in
            guard request.state == .launching else {
                throw LinkRequestQueueError.illegalTransition(id: id, from: request.state, to: .outcomeUnknown)
            }
            request.state = .outcomeUnknown
        }
    }

    public func markCompleted(_ id: UUID, historyEntry: HistoryEntry?) async throws {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        try await moveToTerminal(id, outcome: .succeeded, historyEntry: historyEntry)
    }

    public func markCancelled(_ id: UUID, historyEntry: HistoryEntry?) async throws {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        try await moveToTerminal(id, outcome: .cancelled, historyEntry: historyEntry)
    }

    public func compactTerminal(_ id: UUID) async throws {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        guard let index = terminalRecords.firstIndex(where: { $0.requestID == id }) else {
            throw LinkRequestQueueError.terminalRecordNotFound(id)
        }

        var candidateTerminal = terminalRecords
        candidateTerminal.remove(at: index)
        try await save(pending: pendingRequests, terminal: candidateTerminal)
        terminalRecords = candidateTerminal
    }

    public func discardTerminalHistory(_ id: UUID) async throws {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        guard let index = terminalRecords.firstIndex(where: { $0.requestID == id }) else {
            throw LinkRequestQueueError.terminalRecordNotFound(id)
        }
        let existing = terminalRecords[index]
        guard existing.historyEntry != nil else { return }

        var candidateTerminal = terminalRecords
        candidateTerminal[index] = TerminalRequestRecord(
            requestID: existing.requestID,
            outcome: existing.outcome,
            historyEntry: nil,
            completedAt: existing.completedAt
        )
        try await save(pending: pendingRequests, terminal: candidateTerminal)
        terminalRecords = candidateTerminal
    }

    /// Removes a terminal History payload when it is still present. Missing or
    /// already-scrubbed records are a successful no-op for user deletion flows.
    @discardableResult
    public func discardTerminalHistoryIfPresent(_ id: UUID) async throws -> Bool {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        guard let index = terminalRecords.firstIndex(where: { $0.requestID == id }),
              terminalRecords[index].historyEntry != nil
        else {
            return false
        }
        let existing = terminalRecords[index]
        var candidateTerminal = terminalRecords
        candidateTerminal[index] = TerminalRequestRecord(
            requestID: existing.requestID,
            outcome: existing.outcome,
            historyEntry: nil,
            completedAt: existing.completedAt
        )
        try await save(pending: pendingRequests, terminal: candidateTerminal)
        terminalRecords = candidateTerminal
        return true
    }

    /// Scrubs every terminal History payload with one durable snapshot write,
    /// so a failed clear cannot leave a partially scrubbed journal.
    @discardableResult
    public func discardAllTerminalHistory() async throws -> Int {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }

        let scrubbedCount = terminalRecords.reduce(into: 0) { count, record in
            if record.historyEntry != nil { count += 1 }
        }
        guard scrubbedCount > 0 else { return 0 }
        let candidateTerminal = terminalRecords.map { record in
            TerminalRequestRecord(
                requestID: record.requestID,
                outcome: record.outcome,
                historyEntry: nil,
                completedAt: record.completedAt
            )
        }
        try await save(pending: pendingRequests, terminal: candidateTerminal)
        terminalRecords = candidateTerminal
        return scrubbedCount
    }

    private func mutateRequest(
        _ id: UUID,
        mutation: (inout LinkRequest) throws -> Void
    ) async throws {
        guard let index = pendingRequests.firstIndex(where: { $0.id == id }) else {
            throw LinkRequestQueueError.requestNotFound(id)
        }

        var candidatePending = pendingRequests
        do {
            try mutation(&candidatePending[index])
        } catch {
            throw error
        }
        try await save(pending: candidatePending, terminal: terminalRecords)
        pendingRequests = candidatePending
    }

    private func moveToTerminal(
        _ id: UUID,
        outcome: TerminalRequestOutcome,
        historyEntry: HistoryEntry?
    ) async throws {
        guard let index = pendingRequests.firstIndex(where: { $0.id == id }) else {
            throw LinkRequestQueueError.requestNotFound(id)
        }
        if let historyEntry, historyEntry.requestID != id {
            throw LinkRequestQueueError.mismatchedHistoryRequestID(expected: id, actual: historyEntry.requestID)
        }

        let request = pendingRequests[index]
        var candidatePending = pendingRequests
        candidatePending.remove(at: index)
        let record = TerminalRequestRecord(
            requestID: request.id,
            outcome: outcome,
            historyEntry: historyEntry,
            completedAt: Date()
        )
        let candidateTerminal = terminalRecords + [record]
        try await save(pending: candidatePending, terminal: candidateTerminal)
        let previousPendingCount = pendingRequests.count
        pendingRequests = candidatePending
        terminalRecords = candidateTerminal
        publishPendingCountIfChanged(from: previousPendingCount)
    }

    private func publishPendingCountIfChanged(from previousCount: Int) {
        guard pendingRequests.count != previousCount else { return }
        var terminatedIDs: [UUID] = []
        for (id, continuation) in pendingCountContinuations {
            if case .terminated = continuation.yield(pendingRequests.count) {
                terminatedIDs.append(id)
            }
        }
        for id in terminatedIDs {
            pendingCountContinuations[id] = nil
        }
    }

    private func removePendingCountContinuation(id: UUID) {
        pendingCountContinuations[id] = nil
    }

    private func save(pending: [LinkRequest], terminal: [TerminalRequestRecord]) async throws {
        try await store.save(PendingRequestSnapshot(pendingRequests: pending, terminalRecords: terminal))
    }

    private func acquireMutationPermit() async {
        guard mutationPermitHeld else {
            mutationPermitHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
            mutationWaiterObserver?()
        }
    }

    private func releaseMutationPermit() {
        guard !mutationWaiters.isEmpty else {
            mutationPermitHeld = false
            return
        }
        mutationWaiters.removeFirst().resume()
    }

    private static func validateSnapshot(in snapshot: PendingRequestSnapshot) throws {
        let ids = snapshot.pendingRequests.map(\.id) + snapshot.terminalRecords.map(\.requestID)
        guard Set(ids).count == ids.count else {
            let duplicate = ids.first { id in ids.filter { $0 == id }.count > 1 }!
            throw LinkRequestQueueError.duplicateRequestID(duplicate)
        }
        for terminalRecord in snapshot.terminalRecords {
            if let historyEntry = terminalRecord.historyEntry, historyEntry.requestID != terminalRecord.requestID {
                throw LinkRequestQueueError.mismatchedHistoryRequestID(
                    expected: terminalRecord.requestID,
                    actual: historyEntry.requestID
                )
            }
        }
    }

    private static func requestIDs(in snapshot: PendingRequestSnapshot) -> Set<UUID> {
        Set(snapshot.pendingRequests.map(\.id) + snapshot.terminalRecords.map(\.requestID))
    }
}
