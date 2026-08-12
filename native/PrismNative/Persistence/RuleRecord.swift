import Foundation
import PrismCore
import SwiftData

@Model
final class RuleRecord {
    @Attribute(.unique) var id: UUID
    var isEnabled: Bool
    var matcherPayload: Data
    var targetBrowserID: String
    var priority: Int
    var label: String?
    var validationState: String
    var createdAt: Date
    var updatedAt: Date

    init(rule: RoutingRule) throws {
        id = rule.id
        isEnabled = rule.isEnabled
        matcherPayload = try JSONEncoder().encode(VersionedRuleMatcher(version: 1, matcher: rule.matcher))
        targetBrowserID = rule.targetBrowserID.rawValue
        priority = rule.priority
        label = rule.label
        validationState = rule.validationState.rawValue
        createdAt = rule.createdAt
        updatedAt = rule.updatedAt
    }

    func routingRule() throws -> RoutingRule {
        let payload = try JSONDecoder().decode(VersionedRuleMatcher.self, from: matcherPayload)
        guard payload.version == 1,
              let state = RuleValidationState(rawValue: validationState) else {
            throw PersistenceRecordError.invalidPayload
        }

        return RoutingRule(
            id: id,
            isEnabled: isEnabled,
            matcher: payload.matcher,
            targetBrowserID: BrowserID(rawValue: targetBrowserID),
            priority: priority,
            label: label,
            validationState: state,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func replace(with rule: RoutingRule) throws {
        isEnabled = rule.isEnabled
        matcherPayload = try JSONEncoder().encode(VersionedRuleMatcher(version: 1, matcher: rule.matcher))
        targetBrowserID = rule.targetBrowserID.rawValue
        priority = rule.priority
        label = rule.label
        validationState = rule.validationState.rawValue
        createdAt = rule.createdAt
        updatedAt = rule.updatedAt
    }
}

private struct VersionedRuleMatcher: Codable {
    let version: Int
    let matcher: RuleMatcher
}

enum PersistenceRecordError: Error {
    case invalidPayload
}

extension RuleMatcher {
    var persistenceSortOrder: Int {
        switch self {
        case .exactHost:
            return 0
        case .hostAndSubdomains:
            return 1
        case .urlContains:
            return 2
        case .sourceBundleIdentifier:
            return 3
        }
    }
}
