import AppKit
import Foundation

@MainActor
protocol ApplicationIconProviding: AnyObject {
    func icon(for applicationURL: URL) -> NSImage
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
}
