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
}

struct RuleEditorDraft: Identifiable {
    let id: UUID
    let existingRule: RoutingRule?
    var matchKind: RuleMatchKind
    var matchValue: String
    var sourceDisplayName: String
    var targetBrowserID: BrowserID?
    var label: String
    var isEnabled: Bool

    init(rule: RoutingRule? = nil, prefill: SelectorRulePrefill? = nil, browsers: [BrowserDescriptor]) {
        id = UUID()
        existingRule = rule
        isEnabled = rule?.isEnabled ?? true
        sourceDisplayName = ""

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
                sourceDisplayName = rule.label ?? ""
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
            sourceDisplayName = displayName
            if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                label = displayName
            }
            targetBrowserID = browserID
        case nil:
            matchKind = .domainAndSubdomains
            matchValue = ""
        }
    }

    mutating func changeMatchKind(_ kind: RuleMatchKind) {
        guard kind != matchKind else { return }
        if matchKind == .sourceApplication || kind == .sourceApplication {
            clearSourceSelection()
        }
        matchKind = kind
    }

    mutating func selectSource(bundleIdentifier: String, displayName: String) {
        let trimmedID = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        matchValue = trimmedID
        sourceDisplayName = trimmedName
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            label = trimmedName
        }
    }

    mutating func clearSourceSelection() {
        matchValue = ""
        sourceDisplayName = ""
    }

    var hasSourceSelection: Bool {
        !matchValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSave: Bool {
        matcher != nil && targetBrowserID != nil
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

    func makeRule(now: Date = .now) -> RoutingRule? {
        guard let matcher, let targetBrowserID else { return nil }
        let existing = existingRule
        let trimmedLabel = resolvedLabel
        return RoutingRule(
            id: existing?.id ?? UUID(),
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

    private var resolvedLabel: String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }
        if matchKind == .sourceApplication {
            return sourceDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
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
