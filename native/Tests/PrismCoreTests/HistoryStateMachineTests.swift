import Foundation
import Testing
@testable import PrismCore

@Test func retryUpdatesTheExistingHistoryEntry() throws {
    let request = LinkRequest(
        id: .test(9),
        url: URL(string: "https://example.com/source")!,
        receivedAt: Date(timeIntervalSince1970: 10),
        source: SourceApplication(
            bundleIdentifier: "com.example.Source",
            displayName: "Source",
            confidence: .confirmed
        )
    )
    let sourceURL = URL(string: "https://example.com/source")!
    var entry = HistoryEntry.processing(request: request, sanitizedURL: sourceURL)
    let originalID = entry.id
    let originalRequestID = entry.requestID
    let originalSourceBundleIdentifier = entry.sourceBundleIdentifier
    let originalSourceDisplayName = entry.sourceDisplayName
    let originalCreatedAt = entry.createdAt
    let stateMachine = HistoryStateMachine()

    try stateMachine.apply(
        .launchStarted(
            browserID: "com.apple.Safari",
            browserName: "Safari",
            method: .manual,
            ruleID: .test(10)
        ),
        to: &entry
    )
    try stateMachine.apply(.launchFailed(browserID: "com.apple.Safari", message: "Unavailable"), to: &entry)
    try stateMachine.apply(
        .launchStarted(
            browserID: "com.google.Chrome",
            browserName: "Google Chrome",
            method: .lastUsedBrowser,
            ruleID: .test(11)
        ),
        to: &entry
    )

    #expect(entry.result == .processing)
    #expect(entry.attemptCount == 2)
    #expect(entry.targetBrowserID == "com.google.Chrome")
    #expect(entry.targetDisplayName == "Google Chrome")
    #expect(entry.method == .lastUsedBrowser)
    #expect(entry.matchingRuleID == .test(11))
    #expect(entry.failureReason == nil)
    #expect(entry.completedAt == nil)

    try stateMachine.apply(.launchSucceeded(browserID: "com.google.Chrome", method: .lastUsedBrowser), to: &entry)

    #expect(entry.result == .success)
    #expect(entry.attemptCount == 2)
    #expect(entry.targetBrowserID == "com.google.Chrome")
    #expect(entry.targetDisplayName == "Google Chrome")
    #expect(entry.sanitizedURL == sourceURL)
    #expect(entry.id == originalID)
    #expect(entry.requestID == originalRequestID)
    #expect(entry.sourceBundleIdentifier == originalSourceBundleIdentifier)
    #expect(entry.sourceDisplayName == originalSourceDisplayName)
    #expect(entry.createdAt == originalCreatedAt)
}

@Test func initialLaunchStartsOneAttemptAndPreservesImmutableContext() throws {
    var entry = makeProcessingEntry()
    let originalID = entry.id
    let originalRequestID = entry.requestID
    let originalURL = entry.sanitizedURL
    let originalBundleID = entry.sourceBundleIdentifier
    let originalSourceName = entry.sourceDisplayName
    let originalCreatedAt = entry.createdAt

    try HistoryStateMachine().apply(
        .launchStarted(
            browserID: "com.apple.Safari",
            browserName: "Safari",
            method: .urlRule,
            ruleID: .test(12)
        ),
        to: &entry
    )

    #expect(entry.result == .processing)
    #expect(entry.attemptCount == 1)
    #expect(entry.targetBrowserID == "com.apple.Safari")
    #expect(entry.targetDisplayName == "Safari")
    #expect(entry.method == .urlRule)
    #expect(entry.matchingRuleID == .test(12))
    #expect(entry.failureReason == nil)
    #expect(entry.completedAt == nil)
    #expect(entry.id == originalID)
    #expect(entry.requestID == originalRequestID)
    #expect(entry.sanitizedURL == originalURL)
    #expect(entry.sourceBundleIdentifier == originalBundleID)
    #expect(entry.sourceDisplayName == originalSourceName)
    #expect(entry.createdAt == originalCreatedAt)
}

@Test func failureAndCancellationPreserveActiveTargetAndAttemptCount() throws {
    var entry = makeProcessingEntry()
    let stateMachine = HistoryStateMachine()

    try stateMachine.apply(
        .launchStarted(browserID: "com.apple.Safari", browserName: "Safari", method: .manual, ruleID: .test(13)),
        to: &entry
    )
    try stateMachine.apply(.launchFailed(browserID: "com.apple.Safari", message: "Unavailable"), to: &entry)

    #expect(entry.result == .failure)
    #expect(entry.failureReason == "Unavailable")
    #expect(entry.completedAt != nil)
    #expect(entry.targetBrowserID == "com.apple.Safari")
    #expect(entry.targetDisplayName == "Safari")
    #expect(entry.method == .manual)
    #expect(entry.matchingRuleID == .test(13))
    #expect(entry.attemptCount == 1)

    try stateMachine.apply(.cancelled, to: &entry)

    #expect(entry.result == .cancelled)
    #expect(entry.failureReason == nil)
    #expect(entry.completedAt != nil)
    #expect(entry.targetBrowserID == "com.apple.Safari")
    #expect(entry.targetDisplayName == "Safari")
    #expect(entry.method == .manual)
    #expect(entry.matchingRuleID == .test(13))
    #expect(entry.attemptCount == 1)
}

@Test func cancellationOfFreshProcessingEntryDoesNotAddAnAttempt() throws {
    var entry = makeProcessingEntry()

    try HistoryStateMachine().apply(.cancelled, to: &entry)

    #expect(entry.result == .cancelled)
    #expect(entry.attemptCount == 0)
    #expect(entry.targetBrowserID == nil)
    #expect(entry.method == nil)
    #expect(entry.failureReason == nil)
    #expect(entry.completedAt != nil)
}

@Test func invalidEventsAreRejectedAtomically() throws {
    let stateMachine = HistoryStateMachine()
    var freshEntry = makeProcessingEntry()
    let freshBeforeFailure = freshEntry

    #expect(capturedError { try stateMachine.apply(.launchFailed(browserID: "com.apple.Safari", message: "No launch"), to: &freshEntry) } == .invalidTransition)
    #expect(freshEntry == freshBeforeFailure)

    let freshBeforeSuccess = freshEntry
    #expect(capturedError { try stateMachine.apply(.launchSucceeded(browserID: "com.apple.Safari", method: .manual), to: &freshEntry) } == .invalidTransition)
    #expect(freshEntry == freshBeforeSuccess)

    try stateMachine.apply(
        .launchStarted(browserID: "com.apple.Safari", browserName: "Safari", method: .manual, ruleID: nil),
        to: &freshEntry
    )
    let activeBeforeDuplicateStart = freshEntry
    #expect(capturedError { try stateMachine.apply(.launchStarted(browserID: "com.apple.Safari", browserName: "Safari", method: .manual, ruleID: nil), to: &freshEntry) } == .invalidTransition)
    #expect(freshEntry == activeBeforeDuplicateStart)

    let activeBeforeBrowserMismatch = freshEntry
    #expect(capturedError { try stateMachine.apply(.launchFailed(browserID: "com.google.Chrome", message: "Wrong browser"), to: &freshEntry) } == .browserMismatch)
    #expect(freshEntry == activeBeforeBrowserMismatch)

    let activeBeforeMethodMismatch = freshEntry
    #expect(capturedError { try stateMachine.apply(.launchSucceeded(browserID: "com.apple.Safari", method: .urlRule), to: &freshEntry) } == .methodMismatch)
    #expect(freshEntry == activeBeforeMethodMismatch)

    try stateMachine.apply(.launchFailed(browserID: "com.apple.Safari", message: "Unavailable"), to: &freshEntry)
    let failedBeforeRepeatedFailure = freshEntry
    #expect(capturedError { try stateMachine.apply(.launchFailed(browserID: "com.apple.Safari", message: "Repeated failure"), to: &freshEntry) } == .invalidTransition)
    #expect(freshEntry == failedBeforeRepeatedFailure)

    let failedBeforeSuccess = freshEntry
    #expect(capturedError { try stateMachine.apply(.launchSucceeded(browserID: "com.apple.Safari", method: .manual), to: &freshEntry) } == .invalidTransition)
    #expect(freshEntry == failedBeforeSuccess)
}

@Test func terminalEntriesRejectEveryEventWithoutMutation() throws {
    let stateMachine = HistoryStateMachine()
    var entry = makeProcessingEntry()
    try stateMachine.apply(
        .launchStarted(browserID: "com.apple.Safari", browserName: "Safari", method: .manual, ruleID: nil),
        to: &entry
    )
    try stateMachine.apply(.launchSucceeded(browserID: "com.apple.Safari", method: .manual), to: &entry)
    let completedAt = entry.completedAt

    #expect(entry.attemptCount == 1)
    #expect(entry.completedAt != nil)
    #expect(entry.completedAt! >= entry.createdAt)

    let events: [HistoryEvent] = [
        .launchStarted(browserID: "com.google.Chrome", browserName: "Google Chrome", method: .lastUsedBrowser, ruleID: .test(14)),
        .launchFailed(browserID: "com.apple.Safari", message: "Late failure"),
        .launchSucceeded(browserID: "com.apple.Safari", method: .manual),
        .cancelled
    ]

    for event in events {
        let before = entry
        #expect(capturedError { try stateMachine.apply(event, to: &entry) } == .terminalEntry)
        #expect(entry == before)
        #expect(entry.completedAt == completedAt)
    }
}

private func makeProcessingEntry() -> HistoryEntry {
    let request = LinkRequest(
        id: .test(15),
        url: URL(string: "https://example.com/source")!,
        receivedAt: Date(timeIntervalSince1970: 1),
        source: SourceApplication(
            bundleIdentifier: "com.example.Source",
            displayName: "Source",
            confidence: .confirmed
        )
    )
    return HistoryEntry.processing(request: request, sanitizedURL: URL(string: "https://example.com/sanitized"))
}

private func capturedError(_ operation: () throws -> Void) -> HistoryStateMachineError? {
    do {
        try operation()
        return nil
    } catch let error as HistoryStateMachineError {
        return error
    } catch {
        return nil
    }
}
