import Foundation
import PrismCore

enum RuleUndoResult: Equatable { case removed, alreadyRemoved, changed }

@MainActor
struct RuleSaveUndo {
    private(set) var savedRule: RoutingRule?

    mutating func save(_ rule: RoutingRule, repository: any RuleRepository) throws {
        let isNew = try !repository.all().contains { $0.id == rule.id }
        try repository.upsert(rule)
        // Publish the undo token only after the new rule is durably saved.
        if isNew { savedRule = rule }
    }

    mutating func undo(repository: any RuleRepository) throws -> RuleUndoResult {
        guard let savedRule else { return .alreadyRemoved }
        guard let current = try repository.all().first(where: { $0.id == savedRule.id }) else {
            self.savedRule = nil
            return .alreadyRemoved
        }
        guard current == savedRule else {
            self.savedRule = nil
            return .changed
        }
        // A failed read or delete keeps the token so the user can retry safely.
        try repository.delete(id: savedRule.id)
        self.savedRule = nil
        return .removed
    }
}
