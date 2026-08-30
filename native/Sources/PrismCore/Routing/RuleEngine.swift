import Foundation

public enum SelectorReason: Equatable, Sendable {
    case noMatchingRule
    case rulesPaused
    case targetUnavailable(BrowserID)
    case preferredBrowserUnavailable(BrowserID?)
}

public enum RoutingDecision: Equatable, Sendable {
    case open(browserID: BrowserID, method: RoutingMethod, ruleID: UUID?)
    case ask(reason: SelectorReason)
}

public enum RoutingRuleOrdering {
    public static func sorted(_ rules: [RoutingRule]) -> [RoutingRule] {
        rules.sorted(by: isOrderedBefore)
    }

    public static func isOrderedBefore(_ lhs: RoutingRule, _ rhs: RoutingRule) -> Bool {
        let lhsCategory = category(for: lhs.matcher)
        let rhsCategory = category(for: rhs.matcher)
        if lhsCategory != rhsCategory {
            return lhsCategory < rhsCategory
        }
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func category(for matcher: RuleMatcher) -> Int {
        switch matcher {
        case .exactHost, .hostAndSubdomains, .urlContains:
            return 0
        case .sourceBundleIdentifier:
            return 1
        }
    }
}

public enum URLRuleMatcher {
    public static func matches(_ matcher: RuleMatcher, url: URL) -> Bool {
        switch matcher {
        case let .exactHost(host):
            guard let requestHost = normalizedHost(url.host), let matcherHost = normalizedHost(host) else {
                return false
            }

            return requestHost == matcherHost
        case let .hostAndSubdomains(host):
            guard let requestHost = normalizedHost(url.host), let matcherHost = normalizedHost(host) else {
                return false
            }

            return requestHost == matcherHost || requestHost.hasSuffix(".\(matcherHost)")
        case let .urlContains(value):
            return url.absoluteString.lowercased().contains(value.lowercased())
        case .sourceBundleIdentifier:
            return false
        }
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard var normalized = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        while normalized.last == "." {
            normalized.removeLast()
        }

        return normalized.isEmpty ? nil : normalized
    }
}

public struct RuleEngine: Sendable {
    public init() {}

    public func decide(
        request: LinkRequest,
        rules: [RoutingRule],
        availableBrowserIDs: Set<BrowserID>,
        settings: AppSettings
    ) -> RoutingDecision {
        guard settings.automaticRulesEnabled else {
            return .ask(reason: .rulesPaused)
        }

        if let rule = firstMatchingURLRule(in: rules, request: request) {
            return decision(for: rule, method: .urlRule, availableBrowserIDs: availableBrowserIDs)
        }

        if let rule = firstMatchingSourceRule(in: rules, request: request) {
            return decision(for: rule, method: .sourceRule, availableBrowserIDs: availableBrowserIDs)
        }

        return unmatchedDecision(settings: settings, availableBrowserIDs: availableBrowserIDs)
    }

    private func firstMatchingURLRule(in rules: [RoutingRule], request: LinkRequest) -> RoutingRule? {
        sorted(rules.filter { rule in
            rule.isEnabled &&
                rule.validationState == .valid &&
                isURLRule(rule) &&
                URLRuleMatcher.matches(rule.matcher, url: request.url)
        }).first
    }

    private func firstMatchingSourceRule(
        in rules: [RoutingRule],
        request: LinkRequest
    ) -> RoutingRule? {
        guard request.source.isConfirmedForSourceRules,
              let bundleID = request.source.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty
        else {
            return nil
        }

        return sorted(rules.filter { rule in
            guard case let .sourceBundleIdentifier(ruleBundleID) = rule.matcher else {
                return false
            }

            return rule.isEnabled &&
                rule.validationState == .valid &&
                ruleBundleID == bundleID
        }).first
    }

    private func isURLRule(_ rule: RoutingRule) -> Bool {
        switch rule.matcher {
        case .exactHost, .hostAndSubdomains, .urlContains:
            true
        case .sourceBundleIdentifier:
            false
        }
    }

    private func sorted(_ rules: [RoutingRule]) -> [RoutingRule] {
        RoutingRuleOrdering.sorted(rules)
    }

    private func decision(
        for rule: RoutingRule,
        method: RoutingMethod,
        availableBrowserIDs: Set<BrowserID>
    ) -> RoutingDecision {
        guard availableBrowserIDs.contains(rule.targetBrowserID) else {
            return .ask(reason: .targetUnavailable(rule.targetBrowserID))
        }

        return .open(browserID: rule.targetBrowserID, method: method, ruleID: rule.id)
    }

    private func unmatchedDecision(
        settings: AppSettings,
        availableBrowserIDs: Set<BrowserID>
    ) -> RoutingDecision {
        switch settings.unmatchedBehavior {
        case .alwaysAsk:
            .ask(reason: .noMatchingRule)
        case .preferredBrowser:
            fallbackDecision(
                browserID: settings.preferredBrowserID,
                method: .preferredBrowser,
                availableBrowserIDs: availableBrowserIDs
            )
        case .lastUsedBrowser:
            fallbackDecision(
                browserID: settings.lastUsedBrowserID,
                method: .lastUsedBrowser,
                availableBrowserIDs: availableBrowserIDs
            )
        }
    }

    private func fallbackDecision(
        browserID: BrowserID?,
        method: RoutingMethod,
        availableBrowserIDs: Set<BrowserID>
    ) -> RoutingDecision {
        guard let browserID, availableBrowserIDs.contains(browserID) else {
            return .ask(reason: .preferredBrowserUnavailable(browserID))
        }

        return .open(browserID: browserID, method: method, ruleID: nil)
    }
}
