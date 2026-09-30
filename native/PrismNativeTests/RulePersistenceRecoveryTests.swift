import Foundation
import PrismCore
import SwiftData
import Testing
@testable import PrismNative

@Suite("Rule persistence failure recovery")
@MainActor
struct RulePersistenceRecoveryTests {
    @Test func failedCommitRollsBackInsertedRuleSoRetryStillCreatesUndoToken() throws {
        let container = try ModelContainerFactory.make(inMemory: true).container
        var rejectsCommit = true
        let repository = SwiftDataRuleRepository(container: container) { context in
            if rejectsCommit { throw CommitFailure.injected }
            try context.save()
        }
        let rule = testRule()
        var undo = RuleSaveUndo()
        #expect(throws: CommitFailure.injected) { try undo.save(rule, repository: repository) }
        #expect(try repository.all().isEmpty)
        #expect(undo.savedRule == nil)
        rejectsCommit = false
        try undo.save(rule, repository: repository)
        #expect(undo.savedRule == rule)
        #expect(try undo.undo(repository: repository) == .removed)
        #expect(try repository.all().isEmpty)
    }

    @Test func failedDeleteCommitRetainsRuleAndUndoCanReallyRetry() throws {
        let container = try ModelContainerFactory.make(inMemory: true).container
        var rejectsCommit = false
        let repository = SwiftDataRuleRepository(container: container) { context in
            if rejectsCommit { throw CommitFailure.injected }
            try context.save()
        }
        let rule = testRule()
        var undo = RuleSaveUndo()
        try undo.save(rule, repository: repository)
        rejectsCommit = true
        #expect(throws: CommitFailure.injected) { try undo.undo(repository: repository) }
        #expect(try repository.all() == [rule])
        #expect(undo.savedRule == rule)
        rejectsCommit = false
        #expect(try undo.undo(repository: repository) == .removed)
        #expect(try repository.all().isEmpty)
    }

    @Test func failedEditCommitRestoresPreviousRule() throws {
        let container = try ModelContainerFactory.make(inMemory: true).container
        var rejectsCommit = false
        let repository = SwiftDataRuleRepository(container: container) { context in
            if rejectsCommit { throw CommitFailure.injected }
            try context.save()
        }
        let original = testRule()
        try repository.upsert(original)
        var edited = original
        edited.targetBrowserID = "other"
        rejectsCommit = true
        #expect(throws: CommitFailure.injected) { try repository.upsert(edited) }
        #expect(try repository.all() == [original])
    }

    private func testRule() -> RoutingRule {
        RoutingRule(id: UUID(), isEnabled: true, matcher: .exactHost("example.com"), targetBrowserID: "browser", priority: 0, label: nil, createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
    }
}

private enum CommitFailure: Error { case injected }
