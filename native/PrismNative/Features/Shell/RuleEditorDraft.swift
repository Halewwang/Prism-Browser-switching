import Foundation
import PrismCore

enum RuleMatchKind: String, CaseIterable, Identifiable {
    case exactDomain
    case domainAndSubdomains
    case urlContains
    case sourceApplication

    var id: Self { self }

    var title: String {
        switch self {
        case .exactDomain: "Exact domain"
        case .domainAndSubdomains: "Domain and subdomains"
        case .urlContains: "URL contains"
        case .sourceApplication: "Source application"
        }
    }

    var prompt: String {
        switch self {
        case .exactDomain, .domainAndSubdomains: "example.com"
        case .urlContains: "A word or URL fragment"
        case .sourceApplication: "Application bundle identifier"
        }
    }

    var hint: String {
        switch self {
        case .exactDomain:
            "github.com matches only github.com. www.github.com needs its own rule."
        case .domainAndSubdomains:
            "github.com also matches docs.github.com and www.github.com."
        case .urlContains:
            "Matches when the full link contains this text."
        case .sourceApplication:
            "Choose an installed application. The rule runs when macOS confirms that app sent the link."
        }
    }
}

struct RuleEditorDraft: Identifiable {
    let id: UUID
    let existingRule: RoutingRule?
    var matchKind: RuleMatchKind
    var matchValue: String
    var targetBrowserID: BrowserID?
    var label: String
    var isEnabled: Bool

    init(rule: RoutingRule? = nil, prefill: SelectorRulePrefill? = nil, browsers: [BrowserDescriptor]) {
        id = UUID()
        existingRule = rule
        isEnabled = rule?.isEnabled ?? true

        if let rule {
            targetBrowserID = rule.targetBrowserID
            label = rule.label ?? ""
            switch rule.matcher {
            case let .exactHost(host):
                matchKind = .exactDomain
                matchValue = host
            case let .hostAndSubdomains(host):
                matchKind = .domainAndSubdomains
                matchValue = host
            case let .urlContains(value):
                matchKind = .urlContains
                matchValue = value
            case let .sourceBundleIdentifier(bundleIdentifier):
                matchKind = .sourceApplication
                matchValue = bundleIdentifier
            }
            return
        }

        targetBrowserID = browsers.first(where: { $0.availability == .available })?.id
        label = ""
        switch prefill {
        case let .domain(host, browserID):
            matchKind = .domainAndSubdomains
            matchValue = host
            targetBrowserID = browserID ?? targetBrowserID
        case let .source(bundleIdentifier, displayName, browserID):
            matchKind = .sourceApplication
            matchValue = bundleIdentifier
            label = displayName
            targetBrowserID = browserID
        case .savedRule, nil:
            matchKind = .domainAndSubdomains
            matchValue = ""
        }
    }

    var canSave: Bool {
        matcher != nil && targetBrowserID != nil
    }

    func sourceSupportStatus(
        manifest: SourceSupportManifest,
        operatingSystemVersion: OperatingSystemVersion
    ) -> SourceRuleSupportStatus? {
        guard case let .sourceBundleIdentifier(bundleIdentifier) = matcher else { return nil }
        return manifest.supportStatus(for: bundleIdentifier, on: operatingSystemVersion)
    }

    var matcher: RuleMatcher? {
        let value = matchValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        switch matchKind {
        case .exactDomain:
            guard let host = normalizedHost(value) else { return nil }
            return .exactHost(host)
        case .domainAndSubdomains:
            guard let host = normalizedHost(value) else { return nil }
            return .hostAndSubdomains(host)
        case .urlContains:
            return .urlContains(value)
        case .sourceApplication:
            return .sourceBundleIdentifier(value)
        }
    }

    var scopeDescription: String {
        guard let matcher else { return String(localized: "rules.scope.empty", defaultValue: "Enter a condition to preview its scope.") }
        switch matcher {
        case let .exactHost(host):
            return String(format: String(localized: "rules.scope.exact", defaultValue: "Only the domain %@; subdomains are excluded."), host)
        case let .hostAndSubdomains(host):
            return String(format: String(localized: "rules.scope.subdomains", defaultValue: "%@ and all of its subdomains."), host)
        case let .urlContains(value):
            return String(format: String(localized: "rules.scope.contains", defaultValue: "Any URL containing %@."), value)
        case let .sourceBundleIdentifier(bundleIdentifier):
            return String(format: String(localized: "rules.scope.source", defaultValue: "Links with a confirmed sender matching %@."), bundleIdentifier)
        }
    }

    func makeRule(now: Date = .now) -> RoutingRule? {
        guard let matcher, let targetBrowserID else { return nil }
        let existing = existingRule
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return RoutingRule(
            id: existing?.id ?? id,
            isEnabled: isEnabled,
            matcher: matcher,
            targetBrowserID: targetBrowserID,
            priority: existing?.priority ?? 0,
            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
            validationState: .valid,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func normalizedHost(_ rawValue: String) -> String? {
        let candidate: String
        if let url = URL(string: rawValue), let host = url.host(percentEncoded: false) {
            candidate = host
        } else {
            candidate = rawValue
                .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
                .split(separator: "/", maxSplits: 1)
                .first
                .map(String.init) ?? rawValue
        }
        let normalized = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
