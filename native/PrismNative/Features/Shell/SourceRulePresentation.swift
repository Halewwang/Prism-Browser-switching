import Foundation

struct SourceRulePresentation: Equatable {
    let title: String
    let isInstalled: Bool

    init(bundleIdentifier: String, label: String?, installedDisplayName: String?) {
        let trimmedLabel = Self.visibleName(label)
        let trimmedInstalled = Self.visibleName(installedDisplayName)
        if let trimmedLabel {
            title = trimmedLabel
        } else if let trimmedInstalled {
            title = trimmedInstalled
        } else {
            title = String(localized: "rules.source.untitled", defaultValue: "Unknown Application")
        }
        isInstalled = trimmedInstalled != nil
        _ = bundleIdentifier
    }

    private static func visibleName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeBundleIdentifier(trimmed) else {
            return nil
        }
        return trimmed
    }

    static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("."), !trimmed.contains(" ") else { return false }
        return trimmed.split(separator: ".").count >= 2
    }
}
