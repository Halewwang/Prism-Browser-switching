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

    public init(store: any PendingRequestStore) {
        self.store = store
    }

    public func restore() async throws {
        let loaded = try await store.load()
        try Self.validateUniqueIDs(in: loaded)

        var recovered = loaded
        let hasInterruptedLaunch = recovered.pendingRequests.contains { $0.state == .launching }
        if hasInterruptedLaunch {
            for index in recovered.pendingRequests.indices where recovered.pendingRequests[index].state == .launching {
                recovered.pendingRequests[index].state = .outcomeUnknown
            }
            try await store.save(recovered)
        }

        pendingRequests = recovered.pendingRequests
        terminalRecords = recovered.terminalRecords
        requestIDs = Self.requestIDs(in: recovered)
    }

    @discardableResult
    public func enqueue(_ request: LinkRequest) async throws -> Bool {
        guard !requestIDs.contains(request.id) else { return false }

        let candidatePending = pendingRequests + [request]
        try await save(pending: candidatePending, terminal: terminalRecords)
        pendingRequests = candidatePending
        requestIDs.insert(request.id)
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
        try await mutateRequest(id) { request in
            guard request.state == .queued || request.state == .outcomeUnknown else {
                throw LinkRequestQueueError.illegalTransition(id: id, from: request.state, to: .presenting)
            }
            request.state = .presenting
        }
    }

    public func markLaunching(_ id: UUID, browserID: BrowserID) async throws {
        try await mutateRequest(id) { request in
            guard request.state == .presenting || request.state == .outcomeUnknown else {
                throw LinkRequestQueueError.illegalTransition(id: id, from: request.state, to: .launching)
            }
            request.state = .launching
            request.lastAttemptedBrowserID = browserID
            request.attemptCount += 1
        }
    }

    public func markOutcomeUnknown(_ id: UUID) async throws {
        try await mutateRequest(id) { request in
            guard request.state == .launching else {
                throw LinkRequestQueueError.illegalTransition(id: id, from: request.state, to: .outcomeUnknown)
            }
            request.state = .outcomeUnknown
        }
    }

    public func markCompleted(_ id: UUID, historyEntry: HistoryEntry?) async throws {
        try await moveToTerminal(id, outcome: .succeeded, historyEntry: historyEntry)
    }

    public func markCancelled(_ id: UUID, historyEntry: HistoryEntry?) async throws {
        try await moveToTerminal(id, outcome: .cancelled, historyEntry: historyEntry)
    }

    public func compactTerminal(_ id: UUID) async throws {
        guard let index = terminalRecords.firstIndex(where: { $0.requestID == id }) else {
            throw LinkRequestQueueError.terminalRecordNotFound(id)
        }

        var candidateTerminal = terminalRecords
        candidateTerminal.remove(at: index)
        try await save(pending: pendingRequests, terminal: candidateTerminal)
        terminalRecords = candidateTerminal
        requestIDs.remove(id)
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
        pendingRequests = candidatePending
        terminalRecords = candidateTerminal
    }

    private func save(pending: [LinkRequest], terminal: [TerminalRequestRecord]) async throws {
        try await store.save(PendingRequestSnapshot(pendingRequests: pending, terminalRecords: terminal))
    }

    private static func validateUniqueIDs(in snapshot: PendingRequestSnapshot) throws {
        let ids = snapshot.pendingRequests.map(\.id) + snapshot.terminalRecords.map(\.requestID)
        guard Set(ids).count == ids.count else {
            let duplicate = ids.first { id in ids.filter { $0 == id }.count > 1 }!
            throw LinkRequestQueueError.duplicateRequestID(duplicate)
        }
    }

    private static func requestIDs(in snapshot: PendingRequestSnapshot) -> Set<UUID> {
        Set(snapshot.pendingRequests.map(\.id) + snapshot.terminalRecords.map(\.requestID))
    }
}
