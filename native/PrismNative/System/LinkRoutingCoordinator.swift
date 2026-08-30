import Foundation
import PrismCore

enum SelectorPresentationContext: Equatable, Sendable {
    case normal
    case launchFailed(browserID: BrowserID, message: String)
    case outcomeUnknown(browserID: BrowserID?)
    case noAvailableBrowsers
    case storageUnavailable
}

@MainActor
protocol LinkSelectionPresenting: AnyObject {
    func present(_ request: LinkRequest, context: SelectorPresentationContext)
    func dismiss(requestID: UUID)
}

enum LinkRoutingPassDisposition: Sendable {
    case drained
    case moreWork
    case busy
    case paused
}

enum LinkRoutingCancellationResult: Equatable, Sendable {
    case cancelled
    case notCancelled
}

enum HistoryMaintenanceResult: Equatable, Sendable {
    case completed
    case recoveryPayloadScrubbedButHistoryRemains
    case unavailable
}

@MainActor
protocol LinkRoutingCoordinating: AnyObject {
    @discardableResult
    func processNext(
        while shouldContinue: @escaping @MainActor () -> Bool
    ) async -> LinkRoutingPassDisposition
    @discardableResult
    func presentForExplicitSelection(requestID: UUID) async -> Bool
    func select(browserID: BrowserID, for requestID: UUID) async
    func retry(browserID: BrowserID, for requestID: UUID) async
    func canRetryFromHistory(requestID: UUID) async -> Bool
    @discardableResult
    func retryFromHistory(browserID: BrowserID, requestID: UUID) async -> Bool
    func canDeleteHistoryEntry(requestID: UUID) async -> Bool
    @discardableResult
    func deleteHistoryEntry(_ entry: HistoryEntry) async -> HistoryMaintenanceResult
    func canClearHistoryEntries(_ entries: [HistoryEntry]) async -> Bool
    @discardableResult
    func clearHistoryEntries(_ entries: [HistoryEntry]) async -> HistoryMaintenanceResult
    func markUncertainAttemptCompleted(requestID: UUID) async
    func cancel(requestID: UUID) async
    func cancelForExplicitSelection(requestID: UUID) async -> LinkRoutingCancellationResult
}

@MainActor
protocol LinkRoutingContinuationRequesting: AnyObject {
    func requestRoutingContinuation()
}

extension LinkRoutingCoordinating {
    @discardableResult
    func processNext() async -> LinkRoutingPassDisposition {
        await processNext(while: { true })
    }

    @discardableResult
    func presentForExplicitSelection(requestID _: UUID) async -> Bool { false }

    func canRetryFromHistory(requestID _: UUID) async -> Bool { false }

    @discardableResult
    func retryFromHistory(browserID _: BrowserID, requestID _: UUID) async -> Bool { false }

    func canDeleteHistoryEntry(requestID _: UUID) async -> Bool { false }

    @discardableResult
    func deleteHistoryEntry(_: HistoryEntry) async -> HistoryMaintenanceResult { .unavailable }

    func canClearHistoryEntries(_: [HistoryEntry]) async -> Bool { false }

    @discardableResult
    func clearHistoryEntries(_: [HistoryEntry]) async -> HistoryMaintenanceResult { .unavailable }

    func cancelForExplicitSelection(requestID: UUID) async -> LinkRoutingCancellationResult {
        await cancel(requestID: requestID)
        return .notCancelled
    }
}

@MainActor
protocol PersistenceWarningPresenting: AnyObject {
    func present(_ warning: PersistenceWarning)
}

protocol RuntimeLinkPersistenceWarningPresenting: PersistenceWarningPresenting {
    func updateRuntimeLinkRecoveryState(_ state: RuntimeLinkRecoveryState)
}

@MainActor
final class SelectorPresentationRelay: LinkSelectionPresenting {
    weak var target: (any LinkSelectionPresenting)?
    private(set) var activeRequest: LinkRequest?
    private(set) var activeContext: SelectorPresentationContext?

    func present(_ request: LinkRequest, context: SelectorPresentationContext) {
        activeRequest = request
        activeContext = context
        target?.present(request, context: context)
    }

    func dismiss(requestID: UUID) {
        guard activeRequest?.id == requestID else { return }
        activeRequest = nil
        activeContext = nil
        target?.dismiss(requestID: requestID)
    }
}

@MainActor
final class LinkRoutingCoordinator: LinkRoutingCoordinating {
    private struct RoutingSettings {
        let values: AppSettings
        let canWriteBack: Bool
    }

    private struct AttemptContext {
        let request: LinkRequest
        let browser: BrowserDescriptor
        let method: RoutingMethod
        let ruleID: UUID?
        let startedHistory: HistoryEntry?
        let historySettings: AppSettings
    }

    private struct UncertainAttempt {
        let context: AttemptContext
        let successfulHistory: HistoryEntry?
    }

    private struct FailedHandoffPersistence {
        let context: AttemptContext
        let failedHistory: HistoryEntry?
    }

    private let queue: LinkRequestQueue
    private let ruleRepository: any RuleRepository
    private let historyRepository: any HistoryRepository
    private let historyService: HistoryService
    private let settingsRepository: any SettingsRepository
    private let browserCatalog: any BrowserCataloging
    private let browserLauncher: any BrowserLaunching
    private let sourceManifest: SourceSupportManifest
    private let operatingSystemVersion: OperatingSystemVersion
    private let presenter: any LinkSelectionPresenting
    private let warningPresenter: any PersistenceWarningPresenting
    private weak var outcomeReporter: (any LinkRoutingOutcomeReporting)?
    private let ruleEngine = RuleEngine()
    private let historyStateMachine = HistoryStateMachine()
    private let sanitizer = URLSanitizer.default

    private var historyByRequestID: [UUID: HistoryEntry] = [:]
    private var uncertainAttempts: [UUID: UncertainAttempt] = [:]
    private var failedHandoffPersistence: [UUID: FailedHandoffPersistence] = [:]
    private var storageBlockedRequests: [UUID: LinkRequest] = [:]
    private var attemptingRequestIDs: Set<UUID> = []
    private var activeUserActionRequestIDs: Set<UUID> = []
    private var historyMaintenanceActionInFlight = false
    private var isProcessing = false
    weak var continuationRequester: (any LinkRoutingContinuationRequesting)?

    init(
        queue: LinkRequestQueue,
        ruleRepository: any RuleRepository,
        historyRepository: any HistoryRepository,
        historyService: HistoryService? = nil,
        settingsRepository: any SettingsRepository,
        browserCatalog: any BrowserCataloging,
        browserLauncher: any BrowserLaunching,
        sourceManifest: SourceSupportManifest,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        presenter: any LinkSelectionPresenting,
        warningPresenter: any PersistenceWarningPresenting,
        outcomeReporter: (any LinkRoutingOutcomeReporting)? = nil
    ) {
        self.queue = queue
        self.ruleRepository = ruleRepository
        self.historyRepository = historyRepository
        self.historyService = historyService ?? HistoryService(repository: historyRepository)
        self.settingsRepository = settingsRepository
        self.browserCatalog = browserCatalog
        self.browserLauncher = browserLauncher
        self.sourceManifest = sourceManifest
        self.operatingSystemVersion = operatingSystemVersion
        self.presenter = presenter
        self.warningPresenter = warningPresenter
        self.outcomeReporter = outcomeReporter
    }

    func connectOutcomeReporter(_ reporter: any LinkRoutingOutcomeReporting) {
        outcomeReporter = reporter
    }

    @discardableResult
    func processNext(
        while shouldContinue: @escaping @MainActor () -> Bool
    ) async -> LinkRoutingPassDisposition {
        guard !isProcessing,
              !historyMaintenanceActionInFlight,
              activeUserActionRequestIDs.isEmpty
        else { return .busy }
        isProcessing = true
        defer { isProcessing = false }

        guard shouldContinue() else { return .paused }
        if let uncertain = firstUncertainAttempt() {
            presenter.present(
                uncertain.context.request,
                context: .outcomeUnknown(browserID: uncertain.context.browser.id)
            )
            return .paused
        }
        if let blocked = firstStorageBlockedRequest() {
            presenter.present(blocked, context: .storageUnavailable)
            return .paused
        }
        guard let request = await queue.next() else { return .drained }

        if request.state == .outcomeUnknown {
            presenter.present(
                request,
                context: .outcomeUnknown(browserID: request.lastAttemptedBrowserID)
            )
            return .paused
        }

        let browsers: [BrowserDescriptor]
        do {
            browsers = try await browserCatalog.scan().filter { $0.availability == .available }
        } catch {
            blockForStorage(request)
            return .paused
        }
        guard !browsers.isEmpty else {
            await present(request, as: .noAvailableBrowsers)
            return .paused
        }

        if request.state == .presenting {
            presenter.present(request, context: .normal)
            return .paused
        }

        let settings = loadSettingsForRouting()
        let rules: [RoutingRule]
        do {
            rules = try ruleRepository.all()
        } catch {
            blockForStorage(request)
            return .paused
        }
        // Source rules match confirmed bundle IDs. The bundled support
        // manifest stays available for diagnostics and is not a runtime gate.
        _ = (sourceManifest, operatingSystemVersion)
        let decision = ruleEngine.decide(
            request: request,
            rules: rules,
            availableBrowserIDs: Set(browsers.map(\.id)),
            settings: settings.values
        )

        switch decision {
        case let .open(browserID, method, ruleID):
            guard let browser = browsers.first(where: { $0.id == browserID }) else {
                await present(request, as: .normal)
                return .paused
            }
            let completed = await attempt(
                request: request,
                browser: browser,
                method: method,
                ruleID: ruleID,
                settings: settings
            )
            guard completed, shouldContinue() else { return .paused }
            return await queue.next() == nil ? .drained : .moreWork
        case .ask:
            await present(request, as: .normal)
            return .paused
        }
    }

    @discardableResult
    func presentForExplicitSelection(requestID: UUID) async -> Bool {
        guard !isProcessing,
              !historyMaintenanceActionInFlight,
              activeUserActionRequestIDs.isEmpty,
              attemptingRequestIDs.isEmpty,
              let request = await request(withID: requestID)
        else {
            await report(.storageUnavailable, requestID: requestID)
            return false
        }

        do {
            let hasAvailableBrowser = try await browserCatalog.scan().contains {
                $0.availability == .available
            }
            guard hasAvailableBrowser else {
                await present(request, as: .noAvailableBrowsers)
                await report(.unavailable, requestID: requestID)
                return false
            }
        } catch {
            blockForStorage(request)
            await report(.storageUnavailable, requestID: requestID)
            return false
        }

        await present(request, as: .normal)
        guard let presented = await self.request(withID: requestID),
              presented.state == .presenting
        else {
            await report(.storageUnavailable, requestID: requestID)
            return false
        }
        return true
    }

    func select(browserID: BrowserID, for requestID: UUID) async {
        guard beginUserAction(for: requestID) else { return }
        var shouldRequestContinuation = false
        defer {
            endUserAction(for: requestID)
            if shouldRequestContinuation {
                continuationRequester?.requestRoutingContinuation()
            }
        }

        guard uncertainAttempts[requestID] == nil,
              failedHandoffPersistence[requestID] == nil,
              storageBlockedRequests[requestID] == nil,
              let request = await request(withID: requestID)
        else {
            return
        }
        let browser: BrowserDescriptor
        do {
            guard let available = try await availableBrowser(id: browserID) else {
                presenter.present(request, context: .noAvailableBrowsers)
                await report(.unavailable, requestID: requestID)
                return
            }
            browser = available
        } catch {
            blockForStorage(request)
            await report(.storageUnavailable, requestID: requestID)
            return
        }
        let settings = loadSettingsForRouting()
        if await attempt(
            request: request,
            browser: browser,
            method: .manual,
            ruleID: nil,
            settings: settings,
            ownsUserAction: true
        ) {
            shouldRequestContinuation = true
        }
    }

    func retry(browserID: BrowserID, for requestID: UUID) async {
        guard beginUserAction(for: requestID) else { return }
        let result = await retryWhileOwningUserAction(browserID: browserID, requestID: requestID)
        endUserAction(for: requestID)
        if result.shouldRequestContinuation {
            continuationRequester?.requestRoutingContinuation()
        }
    }

    func canRetryFromHistory(requestID: UUID) async -> Bool {
        guard let request = await request(withID: requestID) else { return false }
        if let failed = failedHandoffPersistence[requestID] {
            return request.state == .launching
                && failed.context.request.id == requestID
        }
        return request.state == .presenting || request.state == .outcomeUnknown
    }

    @discardableResult
    func retryFromHistory(browserID: BrowserID, requestID: UUID) async -> Bool {
        guard beginUserAction(for: requestID) else { return false }
        guard let ownedRequest = await request(withID: requestID) else {
            endUserAction(for: requestID)
            return false
        }
        if let failed = failedHandoffPersistence[requestID] {
            guard ownedRequest.state == .launching,
                  failed.context.browser.id == browserID
            else {
                endUserAction(for: requestID)
                return false
            }
            let repaired = await retryFailedHandoffPersistence(failed)
            endUserAction(for: requestID)
            return repaired
        }
        guard (ownedRequest.state == .presenting || ownedRequest.state == .outcomeUnknown),
              ownedRequest.lastAttemptedBrowserID == browserID
        else {
            endUserAction(for: requestID)
            return false
        }
        let result = await retryWhileOwningUserAction(browserID: browserID, requestID: requestID)
        endUserAction(for: requestID)
        if result.shouldRequestContinuation {
            continuationRequester?.requestRoutingContinuation()
        }
        return result.accepted
    }

    func canDeleteHistoryEntry(requestID: UUID) async -> Bool {
        guard !isProcessing,
              !historyMaintenanceActionInFlight,
              attemptingRequestIDs.isEmpty,
              activeUserActionRequestIDs.isEmpty
        else {
            return false
        }
        return !(await historyRequestIsOwned(requestID))
    }

    @discardableResult
    func deleteHistoryEntry(_ entry: HistoryEntry) async -> HistoryMaintenanceResult {
        guard beginHistoryMaintenanceAction() else { return .unavailable }
        defer { endHistoryMaintenanceAction() }
        guard !(await historyRequestIsOwned(entry.requestID)) else { return .unavailable }
        do {
            try await historyService.delete(entry: entry, queue: queue)
            return .completed
        } catch HistoryServiceError.recoveryPayloadScrubbedButHistoryDeleteFailed {
            warningPresenter.present(.historyNotSaved)
            return .recoveryPayloadScrubbedButHistoryRemains
        } catch {
            warningPresenter.present(.historyNotSaved)
            return .unavailable
        }
    }

    func canClearHistoryEntries(_ entries: [HistoryEntry]) async -> Bool {
        guard !entries.isEmpty,
              !isProcessing,
              !historyMaintenanceActionInFlight,
              attemptingRequestIDs.isEmpty,
              activeUserActionRequestIDs.isEmpty
        else {
            return false
        }
        for entry in entries where await historyRequestIsOwned(entry.requestID) {
            return false
        }
        return true
    }

    @discardableResult
    func clearHistoryEntries(_ entries: [HistoryEntry]) async -> HistoryMaintenanceResult {
        guard !entries.isEmpty, beginHistoryMaintenanceAction() else { return .unavailable }
        defer { endHistoryMaintenanceAction() }
        for entry in entries where await historyRequestIsOwned(entry.requestID) {
            return .unavailable
        }
        do {
            try await historyService.clear(queue: queue)
            return .completed
        } catch HistoryServiceError.recoveryPayloadScrubbedButHistoryClearFailed {
            warningPresenter.present(.historyNotSaved)
            return .recoveryPayloadScrubbedButHistoryRemains
        } catch {
            warningPresenter.present(.historyNotSaved)
            return .unavailable
        }
    }

    private func retryWhileOwningUserAction(
        browserID: BrowserID,
        requestID: UUID
    ) async -> (accepted: Bool, shouldRequestContinuation: Bool) {

        if let failedPersistence = failedHandoffPersistence[requestID] {
            let repaired = await retryFailedHandoffPersistence(failedPersistence)
            return (repaired, false)
        }

        if let uncertain = uncertainAttempts[requestID] {
            do {
                try await queue.markOutcomeUnknown(requestID)
                uncertainAttempts[requestID] = nil
            } catch {
                presenter.present(
                    uncertain.context.request,
                    context: .outcomeUnknown(browserID: uncertain.context.browser.id)
                )
                warningPresenter.present(.recoveryStoreUnavailable)
                await report(.outcomeUnknown, requestID: requestID)
                return (true, false)
            }
        }

        storageBlockedRequests[requestID] = nil
        guard let request = await request(withID: requestID) else { return (false, false) }
        let browser: BrowserDescriptor
        do {
            guard let available = try await availableBrowser(id: browserID) else {
                presenter.present(request, context: .noAvailableBrowsers)
                await report(.unavailable, requestID: requestID)
                return (true, false)
            }
            browser = available
        } catch {
            blockForStorage(request)
            await report(.storageUnavailable, requestID: requestID)
            return (true, false)
        }
        let settings = loadSettingsForRouting()
        let completed = await attempt(
            request: request,
            browser: browser,
            method: .manual,
            ruleID: nil,
            settings: settings,
            ownsUserAction: true
        )
        return (true, completed)
    }

    func markUncertainAttemptCompleted(requestID: UUID) async {
        guard beginUserAction(for: requestID) else { return }
        var shouldRequestContinuation = false
        defer {
            endUserAction(for: requestID)
            if shouldRequestContinuation {
                continuationRequester?.requestRoutingContinuation()
            }
        }

        guard let request = await request(withID: requestID) else { return }
        let settings = loadSettingsForRouting()
        var completedHistory = uncertainAttempts[requestID]?.successfulHistory

        if settings.values.historyEnabled, completedHistory == nil,
           let browserID = request.lastAttemptedBrowserID {
            let browserName = (try? await availableBrowser(id: browserID))?.displayName ?? browserID.rawValue
            var entry = existingOrNewHistory(for: request)
            if entry.result == .processing,
               entry.targetBrowserID == browserID,
               let method = entry.method {
                do {
                    try historyStateMachine.apply(
                        .launchSucceeded(browserID: browserID, method: method),
                        to: &entry
                    )
                    completedHistory = entry
                } catch {
                    completedHistory = historyMarkedCompleted(
                        entry,
                        request: request,
                        browserID: browserID,
                        browserName: browserName
                    )
                }
            } else {
                completedHistory = historyMarkedCompleted(
                    entry,
                    request: request,
                    browserID: browserID,
                    browserName: browserName
                )
            }
        }

        do {
            try await queue.markCompleted(
                requestID,
                historyEntry: settings.values.historyEnabled ? completedHistory : nil
            )
        } catch {
            presenter.present(
                request,
                context: .outcomeUnknown(browserID: request.lastAttemptedBrowserID)
            )
            warningPresenter.present(.recoveryStoreUnavailable)
            await report(.outcomeUnknown, requestID: requestID)
            return
        }

        uncertainAttempts[requestID] = nil
        failedHandoffPersistence[requestID] = nil
        storageBlockedRequests[requestID] = nil
        presenter.dismiss(requestID: requestID)
        await persistTerminalHistoryAndCompact(
            requestID: requestID,
            history: completedHistory,
            settings: settings.values
        )
        await report(.completedWithoutConfirmedHandoff, requestID: requestID)
        shouldRequestContinuation = true
    }

    func cancel(requestID: UUID) async {
        _ = await cancelForExplicitSelection(requestID: requestID)
    }

    func cancelForExplicitSelection(requestID: UUID) async -> LinkRoutingCancellationResult {
        guard beginUserAction(for: requestID) else { return .notCancelled }
        var shouldRequestContinuation = false
        defer {
            endUserAction(for: requestID)
            if shouldRequestContinuation {
                continuationRequester?.requestRoutingContinuation()
            }
        }

        guard let request = await request(withID: requestID) else { return .notCancelled }
        let settings = loadSettingsForRouting()
        let history = settings.values.historyEnabled ? cancellationHistory(for: request) : nil

        do {
            try await queue.markCancelled(requestID, historyEntry: history)
        } catch {
            presenter.present(request, context: .storageUnavailable)
            warningPresenter.present(.recoveryStoreUnavailable)
            storageBlockedRequests[requestID] = request
            await report(.storageUnavailable, requestID: requestID)
            return .notCancelled
        }

        uncertainAttempts[requestID] = nil
        failedHandoffPersistence[requestID] = nil
        storageBlockedRequests[requestID] = nil
        presenter.dismiss(requestID: requestID)
        await persistTerminalHistoryAndCompact(
            requestID: requestID,
            history: history,
            settings: settings.values
        )
        await report(.cancelled, requestID: requestID)
        shouldRequestContinuation = true
        return .cancelled
    }

    private func attempt(
        request: LinkRequest,
        browser: BrowserDescriptor,
        method: RoutingMethod,
        ruleID: UUID?,
        settings: RoutingSettings,
        ownsUserAction: Bool = false
    ) async -> Bool {
        guard ownsUserAction || !activeUserActionRequestIDs.contains(request.id) else { return false }
        guard attemptingRequestIDs.insert(request.id).inserted else { return false }
        defer { attemptingRequestIDs.remove(request.id) }

        let startedHistory = settings.values.historyEnabled
            ? makeStartedHistory(for: request, browser: browser, method: method, ruleID: ruleID)
            : nil
        if let startedHistory {
            historyByRequestID[request.id] = startedHistory
            await upsertHistoryBestEffort(startedHistory, settings: settings.values)
        }

        do {
            try await queue.markLaunching(request.id, browserID: browser.id)
        } catch {
            storageBlockedRequests[request.id] = request
            presenter.present(request, context: .storageUnavailable)
            warningPresenter.present(.recoveryStoreUnavailable)
            await report(.storageUnavailable, requestID: request.id)
            return false
        }

        let context = AttemptContext(
            request: request,
            browser: browser,
            method: method,
            ruleID: ruleID,
            startedHistory: startedHistory,
            historySettings: settings.values
        )

        do {
            _ = try await browserLauncher.open(request.url, with: browser)
        } catch {
            await handleFailedHandoff(context)
            return false
        }

        let successfulHistory = makeSuccessfulHistory(from: startedHistory, context: context)
        do {
            try await queue.markCompleted(
                request.id,
                historyEntry: settings.values.historyEnabled ? successfulHistory : nil
            )
        } catch {
            uncertainAttempts[request.id] = UncertainAttempt(
                context: context,
                successfulHistory: successfulHistory
            )
            presenter.present(request, context: .outcomeUnknown(browserID: browser.id))
            warningPresenter.present(.recoveryStoreUnavailable)
            await report(.outcomeUnknown, requestID: request.id)
            return false
        }

        if let successfulHistory {
            historyByRequestID[request.id] = successfulHistory
        }
        presenter.dismiss(requestID: request.id)
        if method == .manual, settings.canWriteBack {
            saveLastUsedBrowserBestEffort(browser.id, settings: settings.values)
        }
        await persistTerminalHistoryAndCompact(
            requestID: request.id,
            history: successfulHistory,
            settings: settings.values
        )
        await report(.handoffAccepted, requestID: request.id)
        return true
    }

    private func handleFailedHandoff(_ context: AttemptContext) async {
        let failedHistory = makeFailedHistory(from: context.startedHistory, browserID: context.browser.id)
        do {
            try await queue.markPresenting(context.request.id)
        } catch {
            failedHandoffPersistence[context.request.id] = FailedHandoffPersistence(
                context: context,
                failedHistory: failedHistory
            )
            if let failedHistory {
                historyByRequestID[context.request.id] = failedHistory
                await upsertHistoryBestEffort(failedHistory, settings: context.historySettings)
            }
            presenter.present(context.request, context: .storageUnavailable)
            warningPresenter.present(.recoveryStoreUnavailable)
            await report(.storageUnavailable, requestID: context.request.id)
            return
        }

        if let failedHistory {
            historyByRequestID[context.request.id] = failedHistory
            await upsertHistoryBestEffort(failedHistory, settings: context.historySettings)
        }
        let presented = await request(withID: context.request.id) ?? context.request
        presenter.present(
            presented,
            context: .launchFailed(browserID: context.browser.id, message: "launch_failed")
        )
        await report(.handoffFailed, requestID: context.request.id)
    }

    private func retryFailedHandoffPersistence(_ blocked: FailedHandoffPersistence) async -> Bool {
        let settings = loadSettingsForRouting()
        do {
            try await queue.markPresenting(blocked.context.request.id)
        } catch {
            presenter.present(blocked.context.request, context: .storageUnavailable)
            warningPresenter.present(.recoveryStoreUnavailable)
            await report(.storageUnavailable, requestID: blocked.context.request.id)
            return false
        }
        failedHandoffPersistence[blocked.context.request.id] = nil
        if settings.values.historyEnabled, let failedHistory = blocked.failedHistory {
            historyByRequestID[blocked.context.request.id] = failedHistory
            await upsertHistoryBestEffort(failedHistory, settings: settings.values)
        }
        let request = await request(withID: blocked.context.request.id) ?? blocked.context.request
        presenter.present(
            request,
            context: .launchFailed(browserID: blocked.context.browser.id, message: "launch_failed")
        )
        await report(.handoffFailed, requestID: blocked.context.request.id)
        return true
    }

    private func present(_ request: LinkRequest, as context: SelectorPresentationContext) async {
        if request.state == .queued {
            do {
                try await queue.markPresenting(request.id)
            } catch {
                blockForStorage(request)
                return
            }
        }
        let current = await self.request(withID: request.id) ?? request
        presenter.present(current, context: context)
    }

    private func blockForStorage(_ request: LinkRequest) {
        storageBlockedRequests[request.id] = request
        presenter.present(request, context: .storageUnavailable)
        warningPresenter.present(.recoveryStoreUnavailable)
    }

    private func beginUserAction(for requestID: UUID) -> Bool {
        guard !isProcessing,
              !historyMaintenanceActionInFlight,
              attemptingRequestIDs.isEmpty,
              activeUserActionRequestIDs.isEmpty
        else {
            return false
        }
        return activeUserActionRequestIDs.insert(requestID).inserted
    }

    private func endUserAction(for requestID: UUID) {
        activeUserActionRequestIDs.remove(requestID)
    }

    private func beginHistoryMaintenanceAction() -> Bool {
        guard !isProcessing,
              !historyMaintenanceActionInFlight,
              attemptingRequestIDs.isEmpty,
              activeUserActionRequestIDs.isEmpty
        else {
            return false
        }
        historyMaintenanceActionInFlight = true
        return true
    }

    private func endHistoryMaintenanceAction() {
        historyMaintenanceActionInFlight = false
    }

    private func historyRequestIsOwned(_ requestID: UUID) async -> Bool {
        if attemptingRequestIDs.contains(requestID)
            || uncertainAttempts[requestID] != nil
            || failedHandoffPersistence[requestID] != nil
            || storageBlockedRequests[requestID] != nil {
            return true
        }
        return await request(withID: requestID) != nil
    }

    private func firstUncertainAttempt() -> UncertainAttempt? {
        uncertainAttempts.values.min { lhs, rhs in
            lhs.context.request.receivedAt < rhs.context.request.receivedAt
        }
    }

    private func firstStorageBlockedRequest() -> LinkRequest? {
        let failed = failedHandoffPersistence.values.map(\.context.request)
        return (Array(storageBlockedRequests.values) + failed).min { lhs, rhs in
            lhs.receivedAt < rhs.receivedAt
        }
    }

    private func request(withID id: UUID) async -> LinkRequest? {
        await queue.snapshot().first { $0.id == id }
    }

    private func availableBrowser(id: BrowserID) async throws -> BrowserDescriptor? {
        let browsers = try await browserCatalog.scan()
        return browsers.first { $0.id == id && $0.availability == .available }
    }

    private func loadSettingsForRouting() -> RoutingSettings {
        do {
            return RoutingSettings(values: try settingsRepository.load(), canWriteBack: true)
        } catch {
            warningPresenter.present(.settingsNotSaved)
            return RoutingSettings(values: .conservativePersistenceFallback, canWriteBack: false)
        }
    }

    private func existingOrNewHistory(for request: LinkRequest) -> HistoryEntry {
        if let existing = historyByRequestID[request.id] {
            return existing
        }
        if let persisted = try? historyRepository
            .recent(limit: 10_000, newerThan: .distantPast)
            .first(where: { $0.requestID == request.id }) {
            historyByRequestID[request.id] = persisted
            return persisted
        }
        return newHistory(for: request)
    }

    private func newHistory(for request: LinkRequest) -> HistoryEntry {
        HistoryEntry(
            id: request.id,
            requestID: request.id,
            sanitizedURL: sanitizer.sanitize(request.url),
            sourceBundleIdentifier: request.source.bundleIdentifier,
            sourceDisplayName: request.source.displayName,
            targetBrowserID: nil,
            targetDisplayName: nil,
            method: nil,
            result: .processing,
            matchingRuleID: nil,
            failureReason: nil,
            attemptCount: request.attemptCount,
            createdAt: request.receivedAt,
            completedAt: nil
        )
    }

    private func makeStartedHistory(
        for request: LinkRequest,
        browser: BrowserDescriptor,
        method: RoutingMethod,
        ruleID: UUID?
    ) -> HistoryEntry? {
        var entry = existingOrNewHistory(for: request)
        do {
            if entry.result == .processing,
               let activeBrowserID = entry.targetBrowserID {
                try historyStateMachine.apply(
                    .launchFailed(browserID: activeBrowserID, message: "outcome_unknown"),
                    to: &entry
                )
            }
            try historyStateMachine.apply(
                .launchStarted(
                    browserID: browser.id,
                    browserName: browser.displayName,
                    method: method,
                    ruleID: ruleID
                ),
                to: &entry
            )
            return entry
        } catch {
            warningPresenter.present(.historyNotSaved)
            return nil
        }
    }

    private func makeFailedHistory(
        from startedHistory: HistoryEntry?,
        browserID: BrowserID
    ) -> HistoryEntry? {
        guard var entry = startedHistory else { return nil }
        do {
            try historyStateMachine.apply(
                .launchFailed(browserID: browserID, message: "launch_failed"),
                to: &entry
            )
            return entry
        } catch {
            warningPresenter.present(.historyNotSaved)
            return nil
        }
    }

    private func makeSuccessfulHistory(
        from startedHistory: HistoryEntry?,
        context: AttemptContext
    ) -> HistoryEntry? {
        guard var entry = startedHistory else { return nil }
        do {
            try historyStateMachine.apply(
                .launchSucceeded(browserID: context.browser.id, method: context.method),
                to: &entry
            )
            return entry
        } catch {
            warningPresenter.present(.historyNotSaved)
            return nil
        }
    }

    private func cancellationHistory(for request: LinkRequest) -> HistoryEntry? {
        var entry: HistoryEntry
        if let uncertain = uncertainAttempts[request.id] {
            entry = uncertain.context.startedHistory
                ?? newHistory(for: request)
        } else if let failed = failedHandoffPersistence[request.id] {
            entry = failed.context.startedHistory
                ?? newHistory(for: request)
        } else {
            entry = existingOrNewHistory(for: request)
        }
        do {
            if entry.result == .success || entry.result == .cancelled {
                entry = newHistory(for: request)
            }
            try historyStateMachine.apply(.cancelled, to: &entry)
            return entry
        } catch {
            warningPresenter.present(.historyNotSaved)
            return nil
        }
    }

    private func historyMarkedCompleted(
        _ entry: HistoryEntry,
        request: LinkRequest,
        browserID: BrowserID,
        browserName: String
    ) -> HistoryEntry {
        HistoryEntry(
            id: entry.id,
            requestID: request.id,
            sanitizedURL: sanitizer.sanitize(request.url),
            sourceBundleIdentifier: request.source.bundleIdentifier,
            sourceDisplayName: request.source.displayName,
            targetBrowserID: browserID,
            targetDisplayName: browserName,
            method: entry.method ?? .manual,
            result: .success,
            matchingRuleID: entry.matchingRuleID,
            failureReason: nil,
            attemptCount: max(entry.attemptCount, request.attemptCount),
            createdAt: entry.createdAt,
            completedAt: Date()
        )
    }

    private func upsertHistoryBestEffort(_ entry: HistoryEntry, settings: AppSettings) async {
        do {
            try await historyService.upsert(entry, settings: settings)
        } catch {
            warningPresenter.present(.historyNotSaved)
        }
    }

    private func persistTerminalHistoryAndCompact(
        requestID: UUID,
        history: HistoryEntry?,
        settings: AppSettings
    ) async {
        if settings.historyEnabled, let history {
            do {
                try await historyService.upsert(history, settings: settings)
            } catch {
                warningPresenter.present(.historyNotSaved)
                return
            }
        }

        do {
            try await queue.compactTerminal(requestID)
        } catch {
            warningPresenter.present(.recoveryStoreUnavailable)
        }
    }

    private func saveLastUsedBrowserBestEffort(_ browserID: BrowserID, settings: AppSettings) {
        var updated = settings
        updated.lastUsedBrowserID = browserID
        do {
            try settingsRepository.save(updated)
        } catch {
            warningPresenter.present(.settingsNotSaved)
        }
    }

    private func report(_ kind: LinkRoutingOutcome.Kind, requestID: UUID) async {
        await outcomeReporter?.report(LinkRoutingOutcome(requestID: requestID, kind: kind))
    }
}
