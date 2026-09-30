import Foundation
import PrismCore

enum HistoryRuleReference: Equatable {
    case current(RoutingRule)
    case missing(UUID)
    case unavailable(UUID)
    case notRecorded
    case notApplicable
}

/// History records method, target and rule ID, but never a rule-condition snapshot.
/// A lookup is useful for correction; it cannot reconstruct the conditions at routing time.
struct HistoryRoutingExplanation {
    let method: RoutingMethod?
    let targetDisplayName: String?
    let ruleReference: HistoryRuleReference
    var hasRuleSnapshot: Bool { false }

    init(entry: HistoryEntry, currentRules: [RoutingRule]?) {
        method = entry.method
        targetDisplayName = entry.targetDisplayName
        guard entry.method == .urlRule || entry.method == .sourceRule else {
            ruleReference = .notApplicable
            return
        }
        guard let id = entry.matchingRuleID else {
            ruleReference = .notRecorded
            return
        }
        guard let currentRules else {
            ruleReference = .unavailable(id)
            return
        }
        if let rule = currentRules.first(where: { $0.id == id }) {
            ruleReference = .current(rule)
        } else {
            ruleReference = .missing(id)
        }
    }

    var methodExplanation: String {
        switch method {
        case .urlRule: String(localized: "history.explanation.urlRule", defaultValue: "A URL rule selected this browser.")
        case .sourceRule: String(localized: "history.explanation.sourceRule", defaultValue: "A confirmed source application rule selected this browser.")
        case .manual: String(localized: "history.explanation.manual", defaultValue: "You selected this browser in the picker.")
        case .preferredBrowser: String(localized: "history.explanation.preferred", defaultValue: "No rule matched; Prism used the preferred browser.")
        case .lastUsedBrowser: String(localized: "history.explanation.lastUsed", defaultValue: "No rule matched; Prism used the last selected browser.")
        case nil: String(localized: "history.explanation.unrecorded", defaultValue: "No routing method was recorded for this link.")
        }
    }
}
