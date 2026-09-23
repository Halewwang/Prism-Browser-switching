import Foundation
import PrismCore

enum SelectorReasonCopy {
    static func message(_ reason: SelectorReason) -> String {
        switch reason {
        case .noMatchingRule:
            String(localized: "selector.reason.noMatchingRule", defaultValue: "No rule matched this link.")
        case .rulesPaused:
            String(localized: "selector.reason.rulesPaused", defaultValue: "Automatic rules are paused.")
        case .targetUnavailable:
            String(
                localized: "selector.reason.targetUnavailable",
                defaultValue: "The browser in the matching rule is unavailable."
            )
        case .preferredBrowserUnavailable:
            String(
                localized: "selector.reason.preferredUnavailable",
                defaultValue: "The fallback browser is unavailable."
            )
        case .sourceNotConfirmed:
            String(
                localized: "selector.reason.sourceNotConfirmed",
                defaultValue: "The source application was not confirmed, so the source rule did not run."
            )
        }
    }

    static func message(forPersistenceCode code: String) -> String? {
        switch code {
        case SelectorReason.noMatchingRule.persistenceCode:
            message(.noMatchingRule)
        case SelectorReason.rulesPaused.persistenceCode:
            message(.rulesPaused)
        case SelectorReason.targetUnavailable(BrowserID("")).persistenceCode:
            message(.targetUnavailable(BrowserID("")))
        case SelectorReason.preferredBrowserUnavailable(nil).persistenceCode:
            message(.preferredBrowserUnavailable(nil))
        case SelectorReason.sourceNotConfirmed.persistenceCode:
            message(.sourceNotConfirmed)
        default:
            nil
        }
    }
}
