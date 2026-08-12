import AppKit
import Foundation

@MainActor
protocol WorkspaceClient {
    func applicationURLs(toOpen url: URL) -> [URL]
    func open(_ url: URL, with applicationURL: URL) async throws
    func icon(for applicationURL: URL) -> NSImage
}

enum WorkspaceClientError: Error {
    case applicationUnavailable
    case rejected
}

@MainActor
final class SystemWorkspaceClient: WorkspaceClient {
    func applicationURLs(toOpen url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    func open(_ url: URL, with applicationURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: applicationURL.path) else {
            throw WorkspaceClientError.applicationUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if application == nil {
                    continuation.resume(throwing: WorkspaceClientError.rejected)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func icon(for applicationURL: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}
