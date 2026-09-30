import AppKit
import Foundation
import Observation
import PrismCore

enum HistoryViewState: Equatable, Sendable {
    case loading
    case content
    case empty
    case failed
}

enum HistoryConfirmation: Equatable, Sendable {
    case delete(HistoryEntry)
    case clear
}

enum HistoryRowActivity: Equatable, Sendable {
    case retrying
    case reopening
    case deleting
}

struct HistoryRowPresentation: Equatable, Sendable {
    let safeURL: URL?

    var urlText: String { safeURL?.absoluteString ?? "URL not saved" }
    var safeHost: String? { safeURL?.host?.lowercased() }
    var canCopy: Bool { safeURL != nil }
    var canCreateRule: Bool { safeHost != nil }
}

@MainActor
protocol HistoryLinkIntaking: AnyObject {
    func enqueueReopened(url: URL, fromHistoryEntryID: UUID) async -> LinkRequest?
}

extension LinkIntakeService: HistoryLinkIntaking {}

@MainActor
protocol HistoryClipboardWriting: AnyObject {
    func write(_ value: String)
}

@MainActor
final class SystemHistoryClipboard: HistoryClipboardWriting {
    func write(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

@MainActor
final class DiscardingHistoryClipboard: HistoryClipboardWriting {
    func write(_: String) {}
}

@MainActor
protocol HistoryNavigationHandling: AnyObject {
    func openRuleEditor(prefill: SelectorRulePrefill)
}

extension AppEnvironment: HistoryNavigationHandling {
    func openRuleEditor(prefill: SelectorRulePrefill) {
        stageSelectorRulePrefill(prefill)
    }
}

@MainActor
@Observable
final class HistoryViewModel {
    private(set) var state: HistoryViewState = .loading
    private(set) var entries: [HistoryEntry] = []
    private(set) var retryableRequestIDs: Set<UUID> = []
    private(set) var actionMessage: String?
    private(set) var confirmation: HistoryConfirmation?
    private(set) var acceptedReopenedRequest: LinkRequest?
    private(set) var isClearing = false
    private(set) var maintenanceUnavailableRequestIDs: Set<UUID> = []
    private(set) var isClearMaintenanceAvailable = false

    private let historyService: HistoryService
    private let queue: LinkRequestQueue
    private let settings: @MainActor () -> AppSettings
    private let coordinator: any LinkRoutingCoordinating
    private let intake: any HistoryLinkIntaking
    private let clipboard: any HistoryClipboardWriting
    private let navigation: any HistoryNavigationHandling
    private var activeActions: [UUID: HistoryRowActivity] = [:]
    private let sanitizer = URLSanitizer.default

    init(
        historyService: HistoryService,
        queue: LinkRequestQueue,
        settings: @escaping @MainActor () -> AppSettings,
        coordinator: any LinkRoutingCoordinating,
        intake: any HistoryLinkIntaking,
        clipboard: any HistoryClipboardWriting,
        navigation: any HistoryNavigationHandling
    ) {
        self.historyService = historyService
        self.queue = queue
        self.settings = settings
        self.coordinator = coordinator
        self.intake = intake
        self.clipboard = clipboard
        self.navigation = navigation
    }

    var pageState: PageStateModel? {
        switch state {
        case .loading:
            .loading(title: "Loading History", message: "Reading recently handled links…")
        case .empty:
            .empty(
                iconSystemName: "clock.arrow.circlepath",
                title: "Handled links will appear here",
                message: "Links handled by Prism will appear here with their browser and result.",
                actions: [
                    PageStateAction(
                        id: AppShellActionID.testLink.rawValue,
                        title: "Test Link",
                        accessibilityIdentifier: "history.testLink"
                    ),
                ]
            )
        case .failed:
            .failed(
                title: "History could not be loaded",
                message: "Your History remains unchanged. Try reading it again.",
                action: PageStateAction(
                    id: "history.retryLoad",
                    title: "Retry",
                    accessibilityIdentifier: "history.retryLoad"
                )
            )
        case .content:
            nil
        }
    }

    func load() async {
        state = .loading
        actionMessage = nil
        do {
            let loaded = try await historyService.loadRecent(settings: settings())
            var retryable: Set<UUID> = []
            for entry in loaded where entry.result == .failure {
                if await coordinator.canRetryFromHistory(requestID: entry.requestID) {
                    retryable.insert(entry.requestID)
                }
            }
            entries = loaded
            retryableRequestIDs = retryable
            state = loaded.isEmpty ? .empty : .content
            await refreshMaintenanceAvailability()
        } catch {
            retryableRequestIDs = []
            maintenanceUnavailableRequestIDs = []
            isClearMaintenanceAvailable = false
            state = .failed
        }
    }

    func runSession() async {
        let updates = historyService.changeUpdates()
        await load()
        for await _ in updates {
            guard !Task.isCancelled else { break }
            await reloadAfterAction()
        }
    }

    func retry(_ entry: HistoryEntry) async {
        guard entry.result == .failure,
              let browserID = entry.targetBrowserID,
              retryableRequestIDs.contains(entry.requestID),
              beginAction(.retrying, for: entry.requestID)
        else {
            if entry.result == .failure {
                actionMessage = "Retry is unavailable because the original full link is no longer in the recovery queue."
            }
            return
        }
        actionMessage = nil
        let accepted = await coordinator.retryFromHistory(
            browserID: browserID,
            requestID: entry.requestID
        )
        guard accepted else {
            if await coordinator.canRetryFromHistory(requestID: entry.requestID) {
                actionMessage = "Retry is temporarily unavailable while another link action is in progress."
            } else {
                retryableRequestIDs.remove(entry.requestID)
                actionMessage = "Retry is unavailable because the original full link is no longer in the recovery queue."
            }
            await finishActionAndRefreshMaintenance(for: entry.requestID)
            return
        }
        endAction(for: entry.requestID)
        await reloadAfterAction()
    }

    func reopen(_ entry: HistoryEntry) async {
        guard entry.result == .cancelled,
              beginAction(.reopening, for: entry.requestID)
        else { return }
        actionMessage = nil
        guard let url = safePersistedURL(for: entry) else {
            actionMessage = reopenDisabledReason(for: entry)
            await finishActionAndRefreshMaintenance(for: entry.requestID)
            return
        }
        guard let request = await intake.enqueueReopened(
            url: url,
            fromHistoryEntryID: entry.id
        ) else {
            actionMessage = "The link could not be reopened because it was not saved to the recovery queue."
            await finishActionAndRefreshMaintenance(for: entry.requestID)
            return
        }
        acceptedReopenedRequest = request
        await finishActionAndRefreshMaintenance(for: entry.requestID)
    }

    func copyURL(_ entry: HistoryEntry) {
        guard let url = presentation(for: entry).safeURL else { return }
        clipboard.write(url.absoluteString)
    }

    func createRule(_ entry: HistoryEntry) {
        guard let host = presentation(for: entry).safeHost,
              !host.isEmpty
        else {
            actionMessage = "A domain rule cannot be created because this History item has no saved host."
            return
        }
        navigation.openRuleEditor(prefill: .domain(
            host: host,
            browserID: entry.targetBrowserID
        ))
    }

    func editMatchingRule(_ entry: HistoryEntry, currentRules: [RoutingRule]?) {
        guard case let .current(rule) = HistoryRoutingExplanation(entry: entry, currentRules: currentRules).ruleReference else {
            actionMessage = String(localized: "history.explanation.editUnavailable", defaultValue: "The recorded rule is unavailable. Create a new domain rule instead.")
            return
        }
        navigation.openRuleEditor(prefill: .savedRule(id: rule.id))
    }

    func requestDelete(_ entry: HistoryEntry) {
        guard canDelete(entry) else {
            actionMessage = deleteDisabledReason(for: entry)
            return
        }
        confirmation = .delete(entry)
    }

    func requestClear() {
        guard !entries.isEmpty else { return }
        guard canClear else {
            actionMessage = "History cannot be cleared while a link is still being handled. Complete or cancel that link first."
            return
        }
        confirmation = .clear
    }

    func cancelConfirmation() {
        confirmation = nil
    }

    func confirmPendingAction() async {
        let pending = confirmation
        confirmation = nil
        switch pending {
        case let .delete(entry):
            guard canDelete(entry) else {
                actionMessage = deleteDisabledReason(for: entry)
                return
            }
            guard beginAction(.deleting, for: entry.requestID) else { return }
            let result = await coordinator.deleteHistoryEntry(entry)
            endAction(for: entry.requestID)
            switch result {
            case .completed:
                await reloadAfterAction()
            case .recoveryPayloadScrubbedButHistoryRemains:
                actionMessage = "The saved History item remains visible, but its recovery data was removed to protect your privacy."
                await reloadAfterAction()
            case .unavailable:
                actionMessage = "This History item could not be deleted. Nothing was removed."
                await refreshMaintenanceAvailability()
            }
        case .clear:
            guard !isClearing, canClear else {
                actionMessage = "History cannot be cleared while a link is still being handled. Complete or cancel that link first."
                return
            }
            isClearing = true
            let result = await coordinator.clearHistoryEntries(entries)
            isClearing = false
            switch result {
            case .completed:
                await reloadAfterAction()
            case .recoveryPayloadScrubbedButHistoryRemains:
                actionMessage = "Saved History could not be cleared. Recovery data was removed to protect your privacy."
                await reloadAfterAction()
            case .unavailable:
                actionMessage = "History could not be cleared. Nothing was removed."
                await refreshMaintenanceAvailability()
            }
        case nil:
            break
        }
    }

    func dismissActionMessage() {
        actionMessage = nil
    }

    func isPerformingAction(for entry: HistoryEntry) -> Bool {
        activeActions[entry.requestID] != nil
    }

    func activity(for entry: HistoryEntry) -> HistoryRowActivity? {
        activeActions[entry.requestID]
    }

    func canReopen(_ entry: HistoryEntry) -> Bool {
        entry.result == .cancelled && safePersistedURL(for: entry) != nil
    }

    func canDelete(_ entry: HistoryEntry) -> Bool {
        !isPerformingAction(for: entry)
            && entry.result != .processing
            && !retryableRequestIDs.contains(entry.requestID)
            && !maintenanceUnavailableRequestIDs.contains(entry.requestID)
    }

    var canClear: Bool {
        !isClearing && entries.allSatisfy(canDelete) && isClearMaintenanceAvailable
    }

    func deleteDisabledReason(for entry: HistoryEntry) -> String {
        if entry.result == .processing || retryableRequestIDs.contains(entry.requestID) {
            return "Delete is unavailable while Prism can still complete or retry this link. Complete or cancel the link first."
        }
        if maintenanceUnavailableRequestIDs.contains(entry.requestID) {
            return "Delete is unavailable while this link is still being handled. Complete or cancel the link first."
        }
        return "Delete is unavailable while another History action is in progress."
    }

    func presentation(for entry: HistoryEntry) -> HistoryRowPresentation {
        HistoryRowPresentation(safeURL: safePresentedURL(for: entry))
    }

    func reopenDisabledReason(for entry: HistoryEntry) -> String {
        if entry.sanitizedURL == nil {
            return "Reopen is unavailable because URL History was disabled for this link."
        }
        return "Reopen is unavailable because the saved URL is not a safe HTTP or HTTPS link."
    }

    private func safePersistedURL(for entry: HistoryEntry) -> URL? {
        guard let url = entry.sanitizedURL,
              BootstrapLinkBuffer.accepts(url),
              sanitizer.sanitize(url)?.absoluteString == url.absoluteString
        else { return nil }
        return url
    }

    private func safePresentedURL(for entry: HistoryEntry) -> URL? {
        guard let persisted = entry.sanitizedURL,
              let safe = sanitizer.sanitize(persisted),
              BootstrapLinkBuffer.accepts(safe)
        else { return nil }
        return safe
    }

    private func reloadAfterAction() async {
        do {
            let loaded = try await historyService.loadRecent(settings: settings())
            var retryable: Set<UUID> = []
            for entry in loaded where entry.result == .failure {
                if await coordinator.canRetryFromHistory(requestID: entry.requestID) {
                    retryable.insert(entry.requestID)
                }
            }
            entries = loaded
            state = loaded.isEmpty ? .empty : .content
            retryableRequestIDs = retryable
            await refreshMaintenanceAvailability()
        } catch {
            actionMessage = "History changed, but the updated list could not be read. Try loading it again."
            state = .failed
        }
    }

    private func beginAction(_ activity: HistoryRowActivity, for requestID: UUID) -> Bool {
        guard activeActions[requestID] == nil else { return false }
        activeActions[requestID] = activity
        return true
    }

    private func endAction(for requestID: UUID) {
        activeActions[requestID] = nil
    }

    private func finishActionAndRefreshMaintenance(for requestID: UUID) async {
        endAction(for: requestID)
        await refreshMaintenanceAvailability()
    }

    private func refreshMaintenanceAvailability() async {
        guard !entries.isEmpty else {
            maintenanceUnavailableRequestIDs = []
            isClearMaintenanceAvailable = false
            return
        }
        var unavailable: Set<UUID> = []
        for entry in entries {
            if !(await coordinator.canDeleteHistoryEntry(requestID: entry.requestID)) {
                unavailable.insert(entry.requestID)
            }
        }
        maintenanceUnavailableRequestIDs = unavailable
        isClearMaintenanceAvailable = await coordinator.canClearHistoryEntries(entries)
    }
}
