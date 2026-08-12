import Foundation

public enum HistoryEvent: Equatable, Sendable {
    case launchStarted(browserID: BrowserID, browserName: String, method: RoutingMethod, ruleID: UUID?)
    case launchFailed(browserID: BrowserID, message: String)
    case launchSucceeded(browserID: BrowserID, method: RoutingMethod)
    case cancelled
}

public enum HistoryStateMachineError: Error, Equatable, Sendable {
    case terminalEntry
    case invalidTransition
    case browserMismatch
    case methodMismatch
}

public struct HistoryStateMachine: Sendable {
    public init() {}

    public func apply(_ event: HistoryEvent, to entry: inout HistoryEntry) throws {
        guard entry.result != .success, entry.result != .cancelled else {
            throw HistoryStateMachineError.terminalEntry
        }

        var updated = entry

        switch event {
        case let .launchStarted(browserID, browserName, method, ruleID):
            try start(
                browserID: browserID,
                browserName: browserName,
                method: method,
                ruleID: ruleID,
                entry: &updated
            )
        case let .launchFailed(browserID, message):
            try fail(browserID: browserID, message: message, entry: &updated)
        case let .launchSucceeded(browserID, method):
            try succeed(browserID: browserID, method: method, entry: &updated)
        case .cancelled:
            try cancel(entry: &updated)
        }

        entry = updated
    }

    private func start(
        browserID: BrowserID,
        browserName: String,
        method: RoutingMethod,
        ruleID: UUID?,
        entry: inout HistoryEntry
    ) throws {
        let canStart = (entry.result == .processing && hasNoLaunchContext(entry))
            || (entry.result == .failure && hasActiveLaunchContext(entry))
        guard canStart else {
            throw HistoryStateMachineError.invalidTransition
        }

        entry.result = .processing
        entry.targetBrowserID = browserID
        entry.targetDisplayName = browserName
        entry.method = method
        entry.matchingRuleID = ruleID
        entry.failureReason = nil
        entry.completedAt = nil
        entry.attemptCount += 1
    }

    private func fail(browserID: BrowserID, message: String, entry: inout HistoryEntry) throws {
        try requireActiveLaunch(entry)
        guard entry.targetBrowserID == browserID else {
            throw HistoryStateMachineError.browserMismatch
        }

        entry.result = .failure
        entry.failureReason = message
        entry.completedAt = Date()
    }

    private func succeed(browserID: BrowserID, method: RoutingMethod, entry: inout HistoryEntry) throws {
        try requireActiveLaunch(entry)
        guard entry.targetBrowserID == browserID else {
            throw HistoryStateMachineError.browserMismatch
        }
        guard entry.method == method else {
            throw HistoryStateMachineError.methodMismatch
        }

        entry.result = .success
        entry.failureReason = nil
        entry.completedAt = Date()
    }

    private func cancel(entry: inout HistoryEntry) throws {
        let canCancel = (entry.result == .processing && (hasNoLaunchContext(entry) || hasActiveLaunchContext(entry)))
            || (entry.result == .failure && hasActiveLaunchContext(entry))
        guard canCancel else {
            throw HistoryStateMachineError.invalidTransition
        }

        entry.result = .cancelled
        entry.failureReason = nil
        entry.completedAt = Date()
    }

    private func requireActiveLaunch(_ entry: HistoryEntry) throws {
        guard entry.result == .processing, hasActiveLaunchContext(entry) else {
            throw HistoryStateMachineError.invalidTransition
        }
    }

    private func hasNoLaunchContext(_ entry: HistoryEntry) -> Bool {
        entry.targetBrowserID == nil
            && entry.targetDisplayName == nil
            && entry.method == nil
            && entry.matchingRuleID == nil
    }

    private func hasActiveLaunchContext(_ entry: HistoryEntry) -> Bool {
        entry.targetBrowserID != nil
            && entry.targetDisplayName != nil
            && entry.method != nil
    }
}
