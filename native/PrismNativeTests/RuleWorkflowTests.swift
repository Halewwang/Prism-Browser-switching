import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("Rule routing preview")
struct RulePreviewTests {
    @Test func usesProductionOrderingAndReturnsMatchingRuleWithoutLaunching() throws {
        let sourceRule = workflowRule(matcher: .sourceBundleIdentifier("com.example.source"), browser: "source", priority: 0)
        let urlRule = workflowRule(matcher: .hostAndSubdomains("example.com"), browser: "web", priority: 9)
        let source = SourceApplication(bundleIdentifier: "com.example.source", displayName: "Source", confidence: .confirmed)
        let result = try RulePreview.evaluate(urlText: "https://docs.example.com/path", source: source, rules: [sourceRule, urlRule], availableBrowserIDs: ["source", "web"], settings: .defaults)
        #expect(result.decision == .open(browserID: "web", method: .urlRule, ruleID: urlRule.id))
        #expect(result.matchingRule == urlRule)
        #expect(result.source == source)
    }

    @Test func unknownSenderCannotTriggerSourceRuleAndPausedRulesUseSelector() throws {
        let sourceRule = workflowRule(matcher: .sourceBundleIdentifier("com.example.source"), browser: "web")
        let unconfirmed = SourceApplication(bundleIdentifier: "com.example.source", displayName: "Source", confidence: .low)
        let result = try RulePreview.evaluate(urlText: "https://example.com", source: unconfirmed, rules: [sourceRule], availableBrowserIDs: ["web"], settings: .defaults)
        #expect(result.decision == .ask(reason: .sourceNotConfirmed))
        #expect(result.matchingRule == sourceRule)
        var settings = AppSettings.defaults
        settings.automaticRulesEnabled = false
        let paused = try RulePreview.evaluate(urlText: "https://example.com", source: .unknown, rules: [], availableBrowserIDs: ["web"], settings: settings)
        #expect(paused.decision == .ask(reason: .rulesPaused))
        #expect(paused.matchingRule == nil)
    }

    @Test func honorsFallbackAndUnavailableTargets() throws {
        var settings = AppSettings.defaults
        settings.unmatchedBehavior = .preferredBrowser
        settings.preferredBrowserID = "web"
        let fallback = try RulePreview.evaluate(urlText: "https://example.com", source: .unknown, rules: [], availableBrowserIDs: ["web"], settings: settings)
        #expect(fallback.decision == .open(browserID: "web", method: .preferredBrowser, ruleID: nil))
        let rule = workflowRule(matcher: .exactHost("example.com"), browser: "missing")
        let missing = try RulePreview.evaluate(urlText: "https://example.com", source: .unknown, rules: [rule], availableBrowserIDs: ["web"], settings: settings)
        #expect(missing.decision == .ask(reason: .targetUnavailable("missing")))
        #expect(missing.matchingRule == rule)
    }

    @Test(arguments: ["", "example.com", "file:///tmp/test", "javascript:alert(1)", "https://"])
    func rejectsInvalidOrNonWebInputs(_ input: String) {
        #expect(throws: RulePreviewError.invalidURL) {
            try RulePreview.evaluate(urlText: input, source: .unknown, rules: [], availableBrowserIDs: [], settings: .defaults)
        }
    }
}

@Suite("New rule save and undo")
@MainActor
struct RuleSaveUndoTests {
    @Test func undoesOnlyAnActuallySavedNewRule() throws {
        let repository = WorkflowRuleRepository()
        var undo = RuleSaveUndo()
        let rule = workflowRule(matcher: .exactHost("example.com"), browser: "web")
        repository.failSave = true
        #expect(throws: WorkflowFailure.injected) { try undo.save(rule, repository: repository) }
        #expect(undo.savedRule == nil)
        repository.failSave = false
        try undo.save(rule, repository: repository)
        #expect(undo.savedRule == rule)
        #expect(try undo.undo(repository: repository) == .removed)
        #expect(repository.rules.isEmpty)
        #expect(undo.savedRule == nil)
    }

    @Test func failedDeleteAndReadRetainTokenForRetry() throws {
        let repository = WorkflowRuleRepository()
        var undo = RuleSaveUndo()
        let rule = workflowRule(matcher: .exactHost("example.com"), browser: "web")
        try undo.save(rule, repository: repository)
        repository.failRead = true
        #expect(throws: WorkflowFailure.injected) { try undo.undo(repository: repository) }
        #expect(undo.savedRule == rule)
        repository.failRead = false
        repository.failDelete = true
        #expect(throws: WorkflowFailure.injected) { try undo.undo(repository: repository) }
        #expect(undo.savedRule == rule)
        repository.failDelete = false
        #expect(try undo.undo(repository: repository) == .removed)
    }

    @Test func doesNotDeleteARuleChangedAfterSaveOrUndoAnEdit() throws {
        let repository = WorkflowRuleRepository()
        var undo = RuleSaveUndo()
        let original = workflowRule(matcher: .exactHost("example.com"), browser: "web")
        try undo.save(original, repository: repository)
        var changed = original
        changed.targetBrowserID = "other"
        try repository.upsert(changed)
        #expect(try undo.undo(repository: repository) == .changed)
        #expect(repository.rules == [changed])
        #expect(undo.savedRule == nil)
        var freshUndo = RuleSaveUndo()
        try freshUndo.save(changed, repository: repository)
        #expect(freshUndo.savedRule == nil)
    }

    @Test func anAlreadyDeletedRuleConsumesTokenWithoutDeletingAnythingElse() throws {
        let repository = WorkflowRuleRepository()
        var undo = RuleSaveUndo()
        let rule = workflowRule(matcher: .exactHost("example.com"), browser: "web")
        try undo.save(rule, repository: repository)
        try repository.delete(id: rule.id)
        #expect(try undo.undo(repository: repository) == .alreadyRemoved)
        #expect(repository.deleteCount == 1)
        #expect(undo.savedRule == nil)
    }
}

@Suite("Recorded history explanation")
struct HistoryRoutingExplanationTests {
    @Test func explainsTheRecordedMethodInsteadOfReroutingWithCurrentRules() {
        let rule = workflowRule(matcher: .exactHost("other.example"), browser: "new")
        var entry = workflowHistory()
        entry.method = .urlRule
        entry.matchingRuleID = rule.id
        let explanation = HistoryRoutingExplanation(entry: entry, currentRules: [rule])
        #expect(explanation.method == .urlRule)
        #expect(explanation.ruleReference == .current(rule))
        #expect(explanation.targetDisplayName == "Recorded browser")
        #expect(explanation.hasRuleSnapshot == false)
    }

    @Test func deletedAndUnreadableRulesStayExplicitlyUncertain() {
        var entry = workflowHistory()
        entry.method = .sourceRule
        let id = UUID()
        entry.matchingRuleID = id
        #expect(HistoryRoutingExplanation(entry: entry, currentRules: []).ruleReference == .missing(id))
        #expect(HistoryRoutingExplanation(entry: entry, currentRules: nil).ruleReference == .unavailable(id))
        entry.matchingRuleID = nil
        #expect(HistoryRoutingExplanation(entry: entry, currentRules: []).ruleReference == .notRecorded)
    }

    @Test func manualAndFallbackRecordsDoNotClaimAnyMatchedRule() {
        for method in [RoutingMethod.manual, .preferredBrowser, .lastUsedBrowser] {
            var entry = workflowHistory()
            entry.method = method
            entry.matchingRuleID = UUID()
            let explanation = HistoryRoutingExplanation(entry: entry, currentRules: [])
            #expect(explanation.ruleReference == .notApplicable)
            #expect(explanation.method == method)
        }
    }
}

private func workflowRule(matcher: RuleMatcher, browser: BrowserID, priority: Int = 0) -> RoutingRule {
    RoutingRule(id: UUID(), isEnabled: true, matcher: matcher, targetBrowserID: browser, priority: priority, label: nil, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
}

private func workflowHistory() -> HistoryEntry {
    HistoryEntry(id: UUID(), requestID: UUID(), sanitizedURL: URL(string: "https://example.com"), sourceBundleIdentifier: nil, sourceDisplayName: "Unknown", targetBrowserID: "old", targetDisplayName: "Recorded browser", method: .manual, result: .success, matchingRuleID: nil, failureReason: nil, attemptCount: 1, createdAt: Date(timeIntervalSince1970: 2), completedAt: Date(timeIntervalSince1970: 3))
}

private enum WorkflowFailure: Error { case injected }

@MainActor
private final class WorkflowRuleRepository: RuleRepository {
    var rules: [RoutingRule] = []
    var failRead = false
    var failSave = false
    var failDelete = false
    var deleteCount = 0
    func all() throws -> [RoutingRule] {
        if failRead { throw WorkflowFailure.injected }
        return rules
    }
    func upsert(_ rule: RoutingRule) throws {
        if failSave { throw WorkflowFailure.injected }
        rules.removeAll { $0.id == rule.id }
        rules.append(rule)
    }
    func delete(id: UUID) throws {
        if failDelete { throw WorkflowFailure.injected }
        deleteCount += 1
        rules.removeAll { $0.id == id }
    }
}
