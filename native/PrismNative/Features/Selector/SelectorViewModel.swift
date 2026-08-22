import AppKit
import Foundation
import Observation
import PrismCore

enum SelectorRulePrefill: Equatable, Sendable {
    case domain(host: String, browserID: BrowserID?)
    case source(bundleIdentifier: String, displayName: String, browserID: BrowserID)
}

@MainActor
protocol SelectorNavigationHandling: AnyObject {
    func openBrowserManagement()
    func openRuleEditor(prefill: SelectorRulePrefill)
}

@MainActor
protocol SelectorPendingCountProviding: AnyObject {
    func pendingCountUpdates() async -> AsyncStream<Int>
}

@MainActor
final class RecoveryQueuePendingCountProvider: SelectorPendingCountProviding {
    let queue: LinkRequestQueue

    init(queue: LinkRequestQueue) {
        self.queue = queue
    }

    func pendingCountUpdates() async -> AsyncStream<Int> {
        await queue.pendingCountUpdates()
    }
}

@MainActor
@Observable
final class SelectorViewModel {
    let requestID: UUID
    let url: URL
    let source: SourceApplication
    let presentationContext: SelectorPresentationContext

    private(set) var browsers: [BrowserDescriptor]
    private(set) var selectedIndex: Int
    private(set) var revealBrowserID: BrowserID?
    private(set) var pendingCount: Int
    private(set) var isLoading: Bool
    private(set) var scanFailureMessage: String?
    private(set) var isPerformingAction: Bool

    let browserCatalog: any BrowserCataloging
    private let routingCoordinator: any LinkRoutingCoordinating
    private let pendingCountProvider: any SelectorPendingCountProviding
    private let navigationHandler: any SelectorNavigationHandling
    private let eligibleSourceBundleIDs: Set<String>
    @ObservationIgnored private var pendingCountMonitoringTask: Task<Void, Never>?

    init(
        request: LinkRequest,
        context: SelectorPresentationContext,
        browsers: [BrowserDescriptor] = [],
        browserCatalog: any BrowserCataloging,
        routingCoordinator: any LinkRoutingCoordinating,
        pendingCountProvider: any SelectorPendingCountProviding,
        navigationHandler: any SelectorNavigationHandling,
        eligibleSourceBundleIDs: Set<String>
    ) {
        requestID = request.id
        url = request.url
        source = request.source
        presentationContext = context
        let orderedBrowsers = Self.availableAndOrdered(browsers)
        self.browsers = orderedBrowsers
        self.browserCatalog = browserCatalog
        self.routingCoordinator = routingCoordinator
        self.pendingCountProvider = pendingCountProvider
        self.navigationHandler = navigationHandler
        self.eligibleSourceBundleIDs = eligibleSourceBundleIDs
        pendingCount = 0
        isLoading = false
        scanFailureMessage = nil
        isPerformingAction = false

        if let preferredID = context.preferredBrowserID,
           let index = orderedBrowsers.firstIndex(where: { $0.id == preferredID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
    }

    var selectedBrowser: BrowserDescriptor? {
        guard browsers.indices.contains(selectedIndex) else { return nil }
        return browsers[selectedIndex]
    }

    var failedBrowserID: BrowserID? {
        guard case let .launchFailed(browserID, _) = presentationContext else { return nil }
        return browserID
    }

    var accessibleFailureMessage: String? {
        switch presentationContext {
        case let .launchFailed(_, message):
            message
        case .outcomeUnknown:
            String(
                localized: "selector.failure.outcomeUnknown",
                defaultValue: "Prism could not confirm whether the browser opened the link."
            )
        case .storageUnavailable:
            String(
                localized: "selector.failure.storageUnavailable",
                defaultValue: "Prism could not save recovery information. The link is still waiting."
            )
        case .normal, .noAvailableBrowsers:
            scanFailureMessage
        }
    }

    var pendingBadgeText: String? {
        pendingCount >= 2 ? String(pendingCount) : nil
    }

    var pendingAccessibilityValue: String? {
        guard pendingCount >= 2 else { return nil }
        return String(
            localized: "selector.pending.accessibility",
            defaultValue: "\(pendingCount) links waiting"
        )
    }

    var canRescan: Bool { !isLoading }
    var canOpenBrowserManagement: Bool { true }
    var canMarkCompleted: Bool {
        if case .outcomeUnknown = presentationContext { return true }
        return false
    }

    var requiresExplicitRecoveryBrowser: Bool {
        switch presentationContext {
        case let .outcomeUnknown(browserID):
            guard let browserID else { return true }
            return !browsers.contains(where: { $0.id == browserID })
        case .storageUnavailable:
            return presentationContext.preferredBrowserID == nil
        case .normal, .launchFailed, .noAvailableBrowsers:
            return false
        }
    }

    var canCreateDomainRule: Bool {
        guard let host = url.host(percentEncoded: false) else { return false }
        return !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCreateSourceRule: Bool {
        guard source.confidence == .confirmed,
              let bundleIdentifier = source.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty
        else { return false }
        return eligibleSourceBundleIDs.contains(bundleIdentifier)
    }

    func shortcut(forBrowserAt index: Int) -> Int? {
        guard (0 ..< min(browsers.count, 9)).contains(index) else { return nil }
        return index + 1
    }

    func selectPrevious() {
        guard !browsers.isEmpty else { return }
        selectedIndex = selectedIndex == 0 ? browsers.count - 1 : selectedIndex - 1
        revealBrowserID = browsers[selectedIndex].id
    }

    func selectNext() {
        guard !browsers.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % browsers.count
        revealBrowserID = browsers[selectedIndex].id
    }

    func selectShortcut(_ number: Int) {
        let index = number - 1
        guard number >= 1, number <= 9, browsers.indices.contains(index) else { return }
        selectedIndex = index
        revealBrowserID = browsers[index].id
    }

    func canActivateShortcut(_ number: Int) -> Bool {
        !isPerformingAction && browserID(forShortcut: number) != nil
    }

    func activateShortcut(_ number: Int) async {
        guard let browserID = browserID(forShortcut: number) else { return }
        await activateBrowser(id: browserID)
    }

    func selectBrowser(id: BrowserID) {
        guard let index = browsers.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
        revealBrowserID = id
    }

    func prepareForPresentation() async {
        if browsers.isEmpty {
            await rescan()
        }
    }

    @discardableResult
    func startPendingCountMonitoring() -> Task<Void, Never> {
        stopPendingCountMonitoring()
        let pendingCountProvider = pendingCountProvider
        let task = Task { @MainActor [weak self] in
            let updates = await pendingCountProvider.pendingCountUpdates()
            for await count in updates {
                guard !Task.isCancelled, let self else { return }
                pendingCount = max(0, count)
            }
        }
        pendingCountMonitoringTask = task
        return task
    }

    func stopPendingCountMonitoring() {
        pendingCountMonitoringTask?.cancel()
        pendingCountMonitoringTask = nil
    }

    deinit {
        pendingCountMonitoringTask?.cancel()
    }

    func rescan() async {
        guard !isLoading else { return }
        isLoading = true
        scanFailureMessage = nil
        defer { isLoading = false }
        do {
            let scanned = try await browserCatalog.scan()
            browsers = Self.availableAndOrdered(scanned)
            if browsers.isEmpty {
                selectedIndex = 0
                revealBrowserID = nil
            } else {
                selectedIndex = min(selectedIndex, browsers.count - 1)
                revealBrowserID = browsers[selectedIndex].id
            }
        } catch {
            browsers = []
            selectedIndex = 0
            revealBrowserID = nil
            scanFailureMessage = String(
                localized: "selector.browserScan.failed",
                defaultValue: "Prism could not scan for browsers. Try again."
            )
        }
    }

    func activateSelected() async {
        guard let selectedBrowser else { return }
        await activateBrowser(id: selectedBrowser.id)
    }

    func activateBrowser(id: BrowserID) async {
        guard browsers.contains(where: { $0.id == id }), !isPerformingAction else { return }
        selectBrowser(id: id)
        isPerformingAction = true
        defer { isPerformingAction = false }
        switch presentationContext {
        case .normal, .noAvailableBrowsers:
            await routingCoordinator.select(browserID: id, for: requestID)
        case let .launchFailed(failedBrowserID, _):
            if id == failedBrowserID {
                await routingCoordinator.retry(browserID: id, for: requestID)
            } else {
                await routingCoordinator.select(browserID: id, for: requestID)
            }
        case .outcomeUnknown, .storageUnavailable:
            await routingCoordinator.retry(browserID: id, for: requestID)
        }
    }

    func retryRecovery(browserID: BrowserID? = nil) async {
        let candidate = browserID ?? presentationContext.preferredBrowserID
        guard let candidate, browsers.contains(where: { $0.id == candidate }), !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        await routingCoordinator.retry(browserID: candidate, for: requestID)
    }

    func markCompleted() async {
        guard canMarkCompleted, !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        await routingCoordinator.markUncertainAttemptCompleted(requestID: requestID)
    }

    func cancel() async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        await routingCoordinator.cancel(requestID: requestID)
    }

    func openBrowserManagement() {
        navigationHandler.openBrowserManagement()
    }

    func openDomainRule(browserID: BrowserID) {
        guard canCreateDomainRule, let host = url.host(percentEncoded: false) else { return }
        navigationHandler.openRuleEditor(prefill: .domain(host: host, browserID: browserID))
    }

    func openSourceRule(browserID: BrowserID) {
        guard canCreateSourceRule,
              let bundleIdentifier = source.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }
        navigationHandler.openRuleEditor(prefill: .source(
            bundleIdentifier: bundleIdentifier,
            displayName: source.displayName,
            browserID: browserID
        ))
    }

    func browserAccessibilityLabel(at index: Int) -> String {
        guard browsers.indices.contains(index) else { return "" }
        let browser = browsers[index]
        var parts = [browser.displayName]
        if let shortcut = shortcut(forBrowserAt: index) {
            parts.append(String(
                localized: "selector.browser.shortcut",
                defaultValue: "Shortcut \(shortcut)"
            ))
        }
        if index == selectedIndex {
            parts.append(String(localized: "selector.browser.selected", defaultValue: "Selected"))
        }
        if browser.id == failedBrowserID {
            parts.append(String(localized: "selector.browser.failed", defaultValue: "Failed to open"))
        }
        return parts.joined(separator: ", ")
    }

    private static func availableAndOrdered(_ browsers: [BrowserDescriptor]) -> [BrowserDescriptor] {
        browsers
            .filter { $0.availability == .available }
            .sorted {
                if $0.selectorOrder != $1.selectorOrder { return $0.selectorOrder < $1.selectorOrder }
                if $0.displayName != $1.displayName {
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                return $0.id.rawValue < $1.id.rawValue
            }
    }

    private func browserID(forShortcut number: Int) -> BrowserID? {
        guard number >= 1, number <= 9 else { return nil }
        return browsers.indices.contains(number - 1) ? browsers[number - 1].id : nil
    }
}

private extension SelectorPresentationContext {
    var preferredBrowserID: BrowserID? {
        switch self {
        case let .launchFailed(browserID, _):
            browserID
        case let .outcomeUnknown(browserID):
            browserID
        case .normal, .noAvailableBrowsers, .storageUnavailable:
            nil
        }
    }
}
