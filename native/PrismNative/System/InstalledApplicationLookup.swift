import AppKit
import Foundation

enum InstalledApplicationLookup {
    static func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed)
    }

    static func displayName(forBundleIdentifier bundleIdentifier: String) -> String? {
        guard let applicationURL = applicationURL(forBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: applicationURL.path)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        guard let applicationURL = applicationURL(forBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }

    static func identity(at applicationURL: URL) -> (bundleIdentifier: String, displayName: String)? {
        guard let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty
        else {
            return nil
        }
        let displayName = FileManager.default.displayName(atPath: applicationURL.path)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (bundleIdentifier, trimmedName.isEmpty ? bundleIdentifier : trimmedName)
    }
}
