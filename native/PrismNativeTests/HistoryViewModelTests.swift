import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("History model")
@MainActor
struct HistoryViewModelTests {
    @Test func loadReturnsRecentRowsAndRepositoryFailureIsARecoverableFailureNotEmpty() async throws {
        let entry = historyVMEntry(result: .success)
        let repository = HistoryVMRepository(entries: [entry])
        let fixture = makeHistoryVM(repository: repository)

        await fixture.model.load()

        #expect(fixture.model.state == .content)
        #expect(fixture.model.entries == [entry])

        repository.failure = .read
        await fixture.model.load()
        #expect(fixture.model.state == .failed)
        #expect(fixture.model.pageState?.kind == .failed)
        #expect(fixture.model.pageState?.actions.map(\.title) == ["Retry"])
    }

    @Test func failureRetryUsesOnlyCoordinatorWhenRecoveryStillOwnsTheRequest() async {
        let entry = historyVMEntry(result: .failure, targetBrowserID: "com.apple.Safari")
        let coordinator = HistoryVMCoordinator(retryableRequestIDs: [entry.requestID])
        let fixture = makeHistoryVM(entries: [entry], coordinator: coordinator)
        await fixture.model.load()

        await fixture.model.retry(entry)

        #expect(coordinator.retries.map(\.0) == [entry.requestID])
        #expect(coordinator.retries.map(\.1) == ["com.apple.Safari"])
        #expect(fixture.intake.calls.isEmpty)
        #expect(fixture.model.actionMessage == nil)
    }

    @Test func staleFailureCannotRetryAndConcurrentDoubleActionStartsOnlyOnce() async {
        let entry = historyVMEntry(result: .failure, targetBrowserID: "com.apple.Safari")
        let staleCoordinator = HistoryVMCoordinator()
        let stale = makeHistoryVM(entries: [entry], coordinator: staleCoordinator)
        await stale.model.load()
        await stale.model.retry(entry)
        #expect(staleCoordinator.retries.isEmpty)
        #expect(stale.model.actionMessage != nil)

        let suspendedCoordinator = HistoryVMCoordinator(
            retryableRequestIDs: [entry.requestID],
            suspendRetry: true
        )
        let active = makeHistoryVM(entries: [entry], coordinator: suspendedCoordinator)
        await active.model.load()
        let first = Task { @MainActor in await active.model.retry(entry) }
        await suspendedCoordinator.waitUntilRetrySuspended()
        await active.model.retry(entry)
        #expect(suspendedCoordinator.retries.count == 1)
        suspendedCoordinator.releaseRetry()
        await first.value
    }

    @Test func cancelledReopenUsesExactPersistedSafeURLAndLeavesOriginalRowUnchanged() async {
        let original = historyVMEntry(
            result: .cancelled,
            url: "https://example.com/private?safe=value",
            targetBrowserID: nil
        )
        let newRequest = LinkRequest(
            id: historyVMFixedUUID(20),
            url: original.sanitizedURL!,
            receivedAt: Date(timeIntervalSince1970: 20),
            source: .unknown,
            reopenedFromHistoryEntryID: original.id
        )
        let intake = HistoryVMIntake(result: newRequest)
        let fixture = makeHistoryVM(entries: [original], intake: intake)
        await fixture.model.load()

        await fixture.model.reopen(original)

        #expect(intake.calls == [.init(url: original.sanitizedURL!, historyEntryID: original.id)])
        #expect(fixture.model.entries == [original])
        #expect(fixture.model.acceptedReopenedRequest == newRequest)
    }

    @Test func nilOrUnsafeURLCannotReopenOrCopyAndCopyNeverLeaksCredentials() async {
        let nilURL = historyVMEntry(id: historyVMFixedUUID(101), result: .cancelled, url: nil)
        let unsafe = historyVMEntry(
            id: historyVMFixedUUID(102),
            result: .cancelled,
            url: "https://user:password@example.com/private?token=secret#fragment"
        )
        let fixture = makeHistoryVM(entries: [nilURL, unsafe])
        await fixture.model.load()

        await fixture.model.reopen(nilURL)
        await fixture.model.reopen(unsafe)
        fixture.model.copyURL(nilURL)
        fixture.model.copyURL(unsafe)

        #expect(fixture.intake.calls.isEmpty)
        #expect(fixture.clipboard.values == ["https://example.com/private"])
        #expect(!fixture.clipboard.values.joined().contains("password"))
        #expect(!fixture.clipboard.values.joined().contains("token"))
    }

    @Test func rowPresentationCopyAndRuleShareOneResanitizedHTTPURLWithoutLeakingLegacySecrets() async {
        let unsafe = historyVMEntry(
            id: historyVMFixedUUID(103),
            result: .cancelled,
            url: "https://user:password@Sub.Example.com/private?token=secret&password=redacted&api_key=redacted&client_secret=redacted&refresh_token=redacted&safe=value#fragment",
            targetBrowserID: nil
        )
        let nonWeb = historyVMEntry(
            id: historyVMFixedUUID(104),
            result: .cancelled,
            url: "ftp://user:password@example.com/private?token=secret#fragment",
            targetBrowserID: nil
        )
        let navigation = HistoryVMNavigation()
        let fixture = makeHistoryVM(entries: [unsafe, nonWeb], navigation: navigation)
        await fixture.model.load()

        let safePresentation = fixture.model.presentation(for: unsafe)
        let unavailablePresentation = fixture.model.presentation(for: nonWeb)
        fixture.model.copyURL(unsafe)
        fixture.model.copyURL(nonWeb)
        fixture.model.createRule(unsafe)
        fixture.model.createRule(nonWeb)

        #expect(safePresentation.urlText == "https://Sub.Example.com/private?safe=value")
        #expect(safePresentation.safeURL?.absoluteString == safePresentation.urlText)
        #expect(safePresentation.canCopy)
        #expect(safePresentation.canCreateRule)
        #expect(!safePresentation.urlText.contains("user"))
        #expect(!safePresentation.urlText.contains("password"))
        #expect(!safePresentation.urlText.contains("token"))
        #expect(!safePresentation.urlText.contains("api_key"))
        #expect(!safePresentation.urlText.contains("client_secret"))
        #expect(!safePresentation.urlText.contains("refresh_token"))
        #expect(!safePresentation.urlText.contains("fragment"))
        #expect(unavailablePresentation.urlText == "URL not saved")
        #expect(unavailablePresentation.safeURL == nil)
        #expect(!unavailablePresentation.canCopy)
        #expect(!unavailablePresentation.canCreateRule)
        #expect(fixture.clipboard.values == ["https://Sub.Example.com/private?safe=value"])
        #expect(navigation.prefills == [
            .domain(host: "sub.example.com", browserID: nil),
        ])
    }

    @Test func createRuleStagesExactHostEvenWhenCancelledRowHasNoTarget() async {
        let entry = historyVMEntry(
            result: .cancelled,
            url: "https://Sub.Example.com/path?safe=value",
            targetBrowserID: nil
        )
        let navigation = HistoryVMNavigation()
        let fixture = makeHistoryVM(entries: [entry], navigation: navigation)
        await fixture.model.load()

        fixture.model.createRule(entry)

        #expect(navigation.prefills == [
            .domain(host: "sub.example.com", browserID: nil),
        ])
    }

    @Test func deleteAndClearRequireConfirmationAndFailedPersistenceKeepsVisibleRows() async {
        let entry = historyVMEntry(result: .cancelled)
        let repository = HistoryVMRepository(entries: [entry])
        let fixture = makeHistoryVM(repository: repository)
        await fixture.model.load()

        fixture.model.requestDelete(entry)
        #expect(fixture.model.confirmation == .delete(entry))
        fixture.model.cancelConfirmation()
        #expect(repository.deleteCount == 0)
        #expect(fixture.model.entries == [entry])

        repository.failure = .delete
        fixture.model.requestDelete(entry)
        await fixture.model.confirmPendingAction()
        #expect(fixture.model.entries == [entry])
        #expect(fixture.model.actionMessage != nil)

        repository.failure = nil
        fixture.model.requestClear()
        #expect(fixture.model.confirmation == .clear)
        await fixture.model.confirmPendingAction()
        #expect(fixture.model.state == .empty)
        #expect(fixture.model.entries.isEmpty)
    }

    @Test func queueOwnedFailureCannotBeDeletedOrClearedBeforeItIsCompletedOrCancelled() async {
        let retryableFailure = historyVMEntry(
            id: historyVMFixedUUID(105),
            result: .failure,
            targetBrowserID: "com.apple.Safari"
        )
        let completed = historyVMEntry(id: historyVMFixedUUID(106), result: .success)
        let repository = HistoryVMRepository(entries: [retryableFailure, completed])
        let coordinator = HistoryVMCoordinator(retryableRequestIDs: [retryableFailure.requestID])
        let fixture = makeHistoryVM(repository: repository, coordinator: coordinator)
        await fixture.model.load()

        fixture.model.requestDelete(retryableFailure)
        #expect(fixture.model.confirmation == nil)
        #expect(fixture.model.actionMessage?.contains("Complete or cancel") == true)
        fixture.model.requestClear()
        #expect(fixture.model.confirmation == nil)
        #expect(repository.deleteCount == 0)
        #expect(repository.clearCount == 0)
    }

    @Test func historyMaintenanceKeepsItsBusyStateVisibleAndDisablesFurtherDestructiveActions() async {
        let entry = historyVMEntry(id: historyVMFixedUUID(107), result: .success)
        let deleteCoordinator = HistoryVMCoordinator()
        deleteCoordinator.suspendDelete = true
        let deleting = makeHistoryVM(entries: [entry], coordinator: deleteCoordinator)
        await deleting.model.load()

        deleting.model.requestDelete(entry)
        let deleteTask = Task { @MainActor in
            await deleting.model.confirmPendingAction()
        }
        await deleteCoordinator.waitUntilDeleteSuspended()

        #expect(deleting.model.activity(for: entry) == .deleting)
        #expect(deleting.model.isPerformingAction(for: entry))
        #expect(!deleting.model.canDelete(entry))
        #expect(!deleting.model.canClear)
        deleteCoordinator.releaseDelete()
        await deleteTask.value
        #expect(deleting.model.state == .empty)

        let clearEntry = historyVMEntry(id: historyVMFixedUUID(108), result: .success)
        let clearCoordinator = HistoryVMCoordinator()
        clearCoordinator.suspendClear = true
        let clearing = makeHistoryVM(entries: [clearEntry], coordinator: clearCoordinator)
        await clearing.model.load()

        clearing.model.requestClear()
        let clearTask = Task { @MainActor in
            await clearing.model.confirmPendingAction()
        }
        await clearCoordinator.waitUntilClearSuspended()

        #expect(clearing.model.isClearing)
        #expect(!clearing.model.canClear)
        clearCoordinator.releaseClear()
        await clearTask.value
        #expect(clearing.model.state == .empty)
    }

    @Test func partialRecoveryScrubTellsTheUserThatHistoryRemainsVisible() async {
        let entry = historyVMEntry(id: historyVMFixedUUID(109), result: .success)
        let coordinator = HistoryVMCoordinator()
        let fixture = makeHistoryVM(entries: [entry], coordinator: coordinator)
        await fixture.model.load()

        coordinator.deleteHistoryAction = { _ in .recoveryPayloadScrubbedButHistoryRemains }
        fixture.model.requestDelete(entry)
        await fixture.model.confirmPendingAction()
        #expect(fixture.model.entries == [entry])
        #expect(fixture.model.actionMessage == "The saved History item remains visible, but its recovery data was removed to protect your privacy.")

        fixture.model.dismissActionMessage()
        coordinator.clearHistoryAction = { .recoveryPayloadScrubbedButHistoryRemains }
        fixture.model.requestClear()
        await fixture.model.confirmPendingAction()
        #expect(fixture.model.entries == [entry])
        #expect(fixture.model.actionMessage == "Saved History could not be cleared. Recovery data was removed to protect your privacy.")
    }

    @Test func openHistorySessionAutomaticallyReloadsAfterServiceWritesAndCancellationRemovesSubscriber() async throws {
        let first = historyVMEntry(id: historyVMFixedUUID(110), result: .success)
        let second = historyVMEntry(id: historyVMFixedUUID(111), result: .success)
        let repository = HistoryVMRepository(entries: [first])
        let fixture = makeHistoryVM(repository: repository)

        let session = Task { @MainActor in
            await fixture.model.runSession()
        }
        while fixture.historyService.changeSubscriberCount == 0 || fixture.model.state == .loading {
            await Task.yield()
        }

        try await fixture.historyService.upsert(second, settings: .defaults)
        while fixture.model.entries.map(\.id) != [first.id, second.id] {
            await Task.yield()
        }

        #expect(fixture.model.state == .content)
        #expect(fixture.historyService.changeSubscriberCount == 1)
        session.cancel()
        await session.value
        while fixture.historyService.changeSubscriberCount != 0 {
            await Task.yield()
        }
        #expect(fixture.historyService.changeSubscriberCount == 0)
    }
}

@MainActor
private struct HistoryVMFixture {
    let model: HistoryViewModel
    let historyService: HistoryService
    let intake: HistoryVMIntake
    let clipboard: HistoryVMClipboard
}

@MainActor
private func makeHistoryVM(
    entries: [HistoryEntry] = [],
    repository: HistoryVMRepository? = nil,
    coordinator: HistoryVMCoordinator? = nil,
    intake: HistoryVMIntake? = nil,
    navigation: HistoryVMNavigation? = nil
) -> HistoryVMFixture {
    let repository = repository ?? HistoryVMRepository(entries: entries)
    let coordinator = coordinator ?? HistoryVMCoordinator()
    let intake = intake ?? HistoryVMIntake()
    let navigation = navigation ?? HistoryVMNavigation()
    let clipboard = HistoryVMClipboard()
    let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
    coordinator.deleteHistoryAction = { entry in
        do {
            try repository.delete(id: entry.id)
            return .completed
        } catch {
            return .unavailable
        }
    }
    coordinator.clearHistoryAction = {
        do {
            try repository.clear()
            return .completed
        } catch {
            return .unavailable
        }
    }
    let historyService = HistoryService(
        repository: repository,
        now: { Date(timeIntervalSince1970: 200) }
    )
    let model = HistoryViewModel(
        historyService: historyService,
        queue: queue,
        settings: { .defaults },
        coordinator: coordinator,
        intake: intake,
        clipboard: clipboard,
        navigation: navigation
    )
    return HistoryVMFixture(
        model: model,
        historyService: historyService,
        intake: intake,
        clipboard: clipboard
    )
}

@MainActor
private final class HistoryVMRepository: HistoryRepository {
    enum Operation { case read, delete, clear }
    enum Failure: Error { case expected }

    var failure: Operation?
    private var entries: [HistoryEntry]
    private(set) var deleteCount = 0
    private(set) var clearCount = 0

    init(entries: [HistoryEntry]) { self.entries = entries }

    func upsert(_ entry: HistoryEntry) throws {
        entries.removeAll { $0.requestID == entry.requestID }
        entries.append(entry)
    }

    func upsertAndEnforceRetention(_ entry: HistoryEntry, limit: Int, cutoff: Date) throws {
        let previous = entries
        do {
            try upsert(entry)
            try enforceRetention(limit: limit, cutoff: cutoff)
        } catch {
            entries = previous
            throw error
        }
    }

    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry] {
        if failure == .read { throw Failure.expected }
        return Array(entries.filter { $0.createdAt >= newerThan }.prefix(max(limit, 0)))
    }

    func delete(id: UUID) throws {
        deleteCount += 1
        if failure == .delete { throw Failure.expected }
        entries.removeAll { $0.id == id }
    }

    func clear() throws {
        clearCount += 1
        if failure == .clear { throw Failure.expected }
        entries.removeAll()
    }

    func enforceRetention(limit _: Int, cutoff _: Date) throws {}
}

@MainActor
private final class HistoryVMCoordinator: LinkRoutingCoordinating {
    var retryableRequestIDs: Set<UUID>
    private(set) var retries: [(UUID, BrowserID)] = []
    private let suspendRetry: Bool
    private var retrySuspension: CheckedContinuation<Void, Never>?
    var suspendDelete = false
    var suspendClear = false
    private var deleteSuspension: CheckedContinuation<Void, Never>?
    private var clearSuspension: CheckedContinuation<Void, Never>?
    var deleteHistoryAction: @MainActor (HistoryEntry) -> HistoryMaintenanceResult = { _ in .unavailable }
    var clearHistoryAction: @MainActor () -> HistoryMaintenanceResult = { .unavailable }

    init(retryableRequestIDs: Set<UUID> = [], suspendRetry: Bool = false) {
        self.retryableRequestIDs = retryableRequestIDs
        self.suspendRetry = suspendRetry
    }

    func processNext(while _: @escaping @MainActor () -> Bool) async -> LinkRoutingPassDisposition { .drained }
    func select(browserID _: BrowserID, for _: UUID) async {}
    func retry(browserID _: BrowserID, for _: UUID) async {}
    func markUncertainAttemptCompleted(requestID _: UUID) async {}
    func cancel(requestID _: UUID) async {}
    func canRetryFromHistory(requestID: UUID) async -> Bool { retryableRequestIDs.contains(requestID) }

    func retryFromHistory(browserID: BrowserID, requestID: UUID) async -> Bool {
        guard retryableRequestIDs.contains(requestID) else { return false }
        retries.append((requestID, browserID))
        if suspendRetry {
            await withCheckedContinuation { retrySuspension = $0 }
        }
        return true
    }

    func canDeleteHistoryEntry(requestID _: UUID) async -> Bool { true }
    func deleteHistoryEntry(_ entry: HistoryEntry) async -> HistoryMaintenanceResult {
        if suspendDelete {
            await withCheckedContinuation { deleteSuspension = $0 }
        }
        return deleteHistoryAction(entry)
    }
    func canClearHistoryEntries(_: [HistoryEntry]) async -> Bool { true }
    func clearHistoryEntries(_: [HistoryEntry]) async -> HistoryMaintenanceResult {
        if suspendClear {
            await withCheckedContinuation { clearSuspension = $0 }
        }
        return clearHistoryAction()
    }

    func waitUntilRetrySuspended() async {
        while retrySuspension == nil { await Task.yield() }
    }

    func releaseRetry() { retrySuspension?.resume(); retrySuspension = nil }

    func waitUntilDeleteSuspended() async {
        while deleteSuspension == nil { await Task.yield() }
    }

    func releaseDelete() { deleteSuspension?.resume(); deleteSuspension = nil }

    func waitUntilClearSuspended() async {
        while clearSuspension == nil { await Task.yield() }
    }

    func releaseClear() { clearSuspension?.resume(); clearSuspension = nil }
}

@MainActor
private final class HistoryVMIntake: HistoryLinkIntaking {
    struct Call: Equatable { let url: URL; let historyEntryID: UUID }
    private(set) var calls: [Call] = []
    var result: LinkRequest?

    init(result: LinkRequest? = nil) { self.result = result }

    func enqueueReopened(url: URL, fromHistoryEntryID: UUID) async -> LinkRequest? {
        calls.append(.init(url: url, historyEntryID: fromHistoryEntryID))
        return result
    }
}

@MainActor
private final class HistoryVMClipboard: HistoryClipboardWriting {
    private(set) var values: [String] = []
    func write(_ value: String) { values.append(value) }
}

@MainActor
private final class HistoryVMNavigation: HistoryNavigationHandling {
    private(set) var prefills: [SelectorRulePrefill] = []
    func openRuleEditor(prefill: SelectorRulePrefill) { prefills.append(prefill) }
}

private func historyVMEntry(
    id: UUID = historyVMFixedUUID(100),
    result: HistoryResult,
    url: String? = "https://example.com/safe",
    targetBrowserID: BrowserID? = "com.apple.Safari"
) -> HistoryEntry {
    return HistoryEntry(
        id: id,
        requestID: id,
        sanitizedURL: url.flatMap(URL.init(string:)),
        sourceBundleIdentifier: "com.example.source",
        sourceDisplayName: "Source",
        targetBrowserID: targetBrowserID,
        targetDisplayName: targetBrowserID == nil ? nil : "Safari",
        method: targetBrowserID == nil ? nil : .manual,
        result: result,
        matchingRuleID: nil,
        failureReason: result == .failure ? "launch_failed" : nil,
        attemptCount: result == .failure ? 1 : 0,
        createdAt: Date(timeIntervalSince1970: 100),
        completedAt: result == .processing ? nil : Date(timeIntervalSince1970: 101)
    )
}

private func historyVMFixedUUID(_ value: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
}
