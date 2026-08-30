import AppKit
import PrismCore

@MainActor
enum WorkspaceApplicationIcon {
    static func nsImage(for browser: BrowserDescriptor) -> NSImage? {
        if let icon = nsImage(bundleIdentifier: browser.bundleIdentifier) {
            return icon
        }
        if let icon = applicationIcon(at: browser.applicationURL) {
            return icon
        }
        if let alias = wellKnownBundleIdentifier(for: browser),
           alias != browser.bundleIdentifier
        {
            return nsImage(bundleIdentifier: alias)
        }
        return nil
    }

    static func nsImage(bundleIdentifier: String) -> NSImage? {
        let identifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else {
            return nil
        }
        return applicationIcon(at: url)
    }

    static func applicationIcon(at url: URL) -> NSImage? {
        var isDirectory: ObjCBool = false
        guard url.isFileURL,
              url.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func wellKnownBundleIdentifier(for browser: BrowserDescriptor) -> String? {
        let name = browser.displayName.lowercased()
        if name.contains("chrome") { return "com.google.Chrome" }
        if name.contains("safari") { return "com.apple.Safari" }
        if name.contains("arc") { return "company.thebrowser.Browser" }
        if name.contains("firefox") { return "org.mozilla.firefox" }
        if name.contains("edge") { return "com.microsoft.edgemac" }
        if name.contains("brave") { return "com.brave.Browser" }
        return nil
    }
}
