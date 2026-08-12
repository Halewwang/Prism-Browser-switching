import Foundation
import PrismCore

enum BrowserLaunchResult: Equatable, Sendable {
    case handoffSucceeded
}

enum BrowserLaunchError: Error {
    case applicationUnavailable
    case rejected
    case system(Error)
}

@MainActor
protocol BrowserLaunching: AnyObject {
    func open(_ url: URL, with browser: BrowserDescriptor) async throws -> BrowserLaunchResult
}

@MainActor
final class BrowserLauncherService: BrowserLaunching {
    private let workspace: any WorkspaceClient

    init(workspace: any WorkspaceClient = SystemWorkspaceClient()) {
        self.workspace = workspace
    }

    func open(_ url: URL, with browser: BrowserDescriptor) async throws -> BrowserLaunchResult {
        guard browser.availability == .available,
              browser.applicationURL.isFileURL,
              FileManager.default.fileExists(atPath: browser.applicationURL.path),
              FileManager.default.isReadableFile(atPath: browser.applicationURL.path) else {
            throw BrowserLaunchError.applicationUnavailable
        }

        do {
            try await workspace.open(url, with: browser.applicationURL)
            return .handoffSucceeded
        } catch WorkspaceClientError.applicationUnavailable {
            throw BrowserLaunchError.applicationUnavailable
        } catch WorkspaceClientError.rejected {
            throw BrowserLaunchError.rejected
        } catch WorkspaceClientError.system(let error) {
            throw BrowserLaunchError.system(error)
        } catch {
            throw BrowserLaunchError.system(error)
        }
    }
}
