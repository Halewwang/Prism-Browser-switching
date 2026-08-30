import Foundation
import PrismCore

enum WorkspaceCopy {
    static func rulePreviewSentence(for rule: RoutingRule, browserName: String) -> String {
        let value = rule.matcherValue
        switch rule.matcher {
        case .exactHost:
            return formatted("When a link is for the exact domain %@, Prism opens it in %@.", value, browserName)
        case .hostAndSubdomains:
            return formatted("When a link matches %@ or any of its subdomains, Prism opens it in %@.", value, browserName)
        case .urlContains:
            return formatted("When a link contains “%@”, Prism opens it in %@.", value, browserName)
        case .sourceBundleIdentifier:
            return formatted(
                "When a confirmed source application is %@, Prism opens the link in %@.",
                value,
                browserName
            )
        }
    }

    static func selectorPosition(order: Int, count: Int, locale: Locale = .current) -> String {
        String(
            format: String(localized: "Selector position %lld of %lld"),
            locale: locale,
            Int64(order + 1),
            Int64(count)
        )
    }

    static func keyboardShortcut(order: Int) -> String? {
        guard (0..<9).contains(order) else { return nil }
        return String(format: String(localized: "Keyboard shortcut %lld"), locale: .current, Int64(order + 1))
    }

    static func ruleReferenceCount(_ count: Int, locale: Locale = .current) -> String {
        let key = count == 1 ? "Used by %lld rule" : "Used by %lld rules"
        return String(format: NSLocalizedString(key, comment: ""), locale: locale, Int64(count))
    }

    static func historyLimit(_ limit: Int, locale: Locale = .current) -> String {
        String(format: String(localized: "Keep up to %lld links"), locale: locale, Int64(limit))
    }

    static func historyRetention(_ days: Int, locale: Locale = .current) -> String {
        String(format: String(localized: "Keep links for %lld days"), locale: locale, Int64(days))
    }

    static func defaultHandlerSentence(for state: DefaultHandlerState?) -> String {
        switch state {
        case .active:
            String(localized: "Prism is the default web link handler.")
        case .inactive:
            String(localized: "Prism is not the default web link handler.")
        case nil:
            String(localized: "Prism is checking the default web link handler.")
        }
    }

    static func languageSentenceLead() -> String {
        String(localized: "Prism uses")
    }

    static func languageSentenceTrail() -> String {
        String(localized: "for the interface.")
    }

    static func unmatchedSentenceLead() -> String {
        String(localized: "When no rule matches, Prism will")
    }

    static func preferredBrowserSentenceLead() -> String {
        String(localized: "Open unmatched links in")
    }

    private static func formatted(_ key: String, _ values: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), locale: .current, arguments: values)
    }
}

extension RoutingRule {
    var isSourceRule: Bool {
        if case .sourceBundleIdentifier = matcher { return true }
        return false
    }

    var matcherDisplayName: String {
        switch matcher {
        case .exactHost: String(localized: "Exact domain")
        case .hostAndSubdomains: String(localized: "Domain and subdomains")
        case .urlContains: String(localized: "URL contains")
        case .sourceBundleIdentifier: String(localized: "Source application")
        }
    }

    var displayName: String {
        if let label, !label.isEmpty { return label }
        return matcherValue
    }

    var matcherIcon: String {
        switch matcher {
        case .sourceBundleIdentifier: "app.badge"
        case .exactHost, .hostAndSubdomains, .urlContains: "globe"
        }
    }

    var matcherValue: String {
        switch matcher {
        case let .exactHost(value),
             let .hostAndSubdomains(value),
             let .urlContains(value),
             let .sourceBundleIdentifier(value):
            value
        }
    }
}

extension UnmatchedBehavior {
    var sentenceTitle: LocalizedStringResource {
        switch self {
        case .alwaysAsk: "always ask"
        case .preferredBrowser: "open in the preferred browser"
        case .lastUsedBrowser: "open in the last used browser"
        }
    }
}

extension AppLanguage {
    var sentenceTitle: LocalizedStringResource {
        switch self {
        case .system: "the system language"
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        }
    }
}

extension BrowserOrigin {
    var displayName: LocalizedStringResource {
        switch self {
        case .custom: "Custom"
        case .system: "Installed"
        }
    }
}

extension BrowserAvailability {
    var displayName: LocalizedStringResource {
        switch self {
        case .available: "Available"
        case .unavailable: "Unavailable"
        }
    }
}
