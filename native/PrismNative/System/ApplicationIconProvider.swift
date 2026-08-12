import AppKit
import Foundation

@MainActor
protocol ApplicationIconProviding: AnyObject {
    func icon(for applicationURL: URL) -> NSImage
    func icon(bundleIdentifier: String) -> NSImage?
}

@MainActor
final class ApplicationIconProvider: ApplicationIconProviding {
    private let workspace: any WorkspaceClient

    init(workspace: any WorkspaceClient = SystemWorkspaceClient()) {
        self.workspace = workspace
    }

    func icon(for applicationURL: URL) -> NSImage {
        workspace.icon(for: applicationURL)
    }

    func icon(bundleIdentifier: String) -> NSImage? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return workspace.icon(for: applicationURL)
    }
}
