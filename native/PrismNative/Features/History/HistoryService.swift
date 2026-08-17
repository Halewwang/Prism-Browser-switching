import Foundation
import PrismCore

/// Describes a deletion which safely removed recovery data before the visible
/// History record could be removed. The caller must not claim that nothing
/// changed in this case: the recoverable payload has deliberately gone away.
enum HistoryServiceError: Error, Equatable, Sendable {
    case recoveryPayloadScrubbedButHistoryDeleteFailed
    case recoveryPayloadScrubbedButHistoryClearFailed
}

@MainActor
final class HistoryService {
    private let repository: any HistoryRepository
    private let now: @MainActor () -> Date
    private var mutationPermitHeld = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    private var changeContinuations: [UUID: AsyncStream<UInt64>.Continuation] = [:]
    private(set) var changeRevision: UInt64 = 0

    var changeSubscriberCount: Int { changeContinuations.count }

    init(
        repository: any HistoryRepository,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.repository = repository
        self.now = now
    }

    func loadRecent(settings: AppSettings) async throws -> [HistoryEntry] {
        try await withMutationPermit {
            try enforceRetention(settings: settings)
            return try repository.recent(
                limit: max(settings.historyLimit, 0),
                newerThan: cutoff(for: settings)
            )
        }
    }

    func upsert(_ entry: HistoryEntry, settings: AppSettings) async throws {
        try await withMutationPermit {
            try repository.upsertAndEnforceRetention(
                entry,
                limit: max(settings.historyLimit, 0),
                cutoff: cutoff(for: settings)
            )
            publishChange()
        }
    }

    func delete(entry: HistoryEntry, queue: LinkRequestQueue) async throws {
        try await withMutationPermit {
            let didScrubRecoveryPayload = try await queue.discardTerminalHistoryIfPresent(entry.requestID)
            do {
                try repository.delete(id: entry.id)
            } catch {
                if didScrubRecoveryPayload {
                    throw HistoryServiceError.recoveryPayloadScrubbedButHistoryDeleteFailed
                }
                throw error
            }
            publishChange()
        }
    }

    func clear(queue: LinkRequestQueue) async throws {
        try await withMutationPermit {
            let scrubbedRecoveryPayloadCount = try await queue.discardAllTerminalHistory()
            do {
                try repository.clear()
            } catch {
                if scrubbedRecoveryPayloadCount > 0 {
                    throw HistoryServiceError.recoveryPayloadScrubbedButHistoryClearFailed
                }
                throw error
            }
            publishChange()
        }
    }

    func changeUpdates() -> AsyncStream<UInt64> {
        let subscriptionID = UUID()
        return AsyncStream { continuation in
            changeContinuations[subscriptionID] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.changeContinuations[subscriptionID] = nil
                }
            }
        }
    }

    func reconcile(
        queue: LinkRequestQueue,
        settings: AppSettings,
        warning: (PersistenceWarning) -> Void
    ) async -> Bool {
        await withMutationPermit {
            var historyChanged = false
            do {
                try enforceRetention(settings: settings)
            } catch {
                warning(.historyNotSaved)
            }
            let terminalRecords = await queue.terminalSnapshot()
            for terminalRecord in terminalRecords {
                if settings.historyEnabled, let historyEntry = terminalRecord.historyEntry {
                    do {
                        try repository.upsertAndEnforceRetention(
                            historyEntry,
                            limit: max(settings.historyLimit, 0),
                            cutoff: cutoff(for: settings)
                        )
                        historyChanged = true
                    } catch {
                        warning(.historyNotSaved)
                        continue
                    }
                } else if !settings.historyEnabled, terminalRecord.historyEntry != nil {
                    do {
                        try await queue.discardTerminalHistory(terminalRecord.requestID)
                    } catch {
                        warning(.recoveryStoreUnavailable)
                        continue
                    }
                }

                do {
                    try await queue.compactTerminal(terminalRecord.requestID)
                } catch {
                    warning(.recoveryStoreUnavailable)
                }
            }
            if historyChanged {
                publishChange()
            }
            return (await queue.terminalSnapshot()).isEmpty
        }
    }

    private func enforceRetention(settings: AppSettings) throws {
        try repository.enforceRetention(
            limit: max(settings.historyLimit, 0),
            cutoff: cutoff(for: settings)
        )
    }

    private func cutoff(for settings: AppSettings) -> Date {
        let secondsPerDay = 24.0 * 60.0 * 60.0
        return now().addingTimeInterval(-Double(max(settings.historyRetentionDays, 0)) * secondsPerDay)
    }

    private func publishChange() {
        changeRevision &+= 1
        for continuation in changeContinuations.values {
            continuation.yield(changeRevision)
        }
    }

    private func withMutationPermit<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        await acquireMutationPermit()
        defer { releaseMutationPermit() }
        return try await operation()
    }

    private func acquireMutationPermit() async {
        guard !mutationPermitHeld else {
            await withCheckedContinuation { continuation in
                mutationWaiters.append(continuation)
            }
            return
        }
        mutationPermitHeld = true
    }

    private func releaseMutationPermit() {
        guard !mutationWaiters.isEmpty else {
            mutationPermitHeld = false
            return
        }
        mutationWaiters.removeFirst().resume()
    }
}
