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
    private let profileDiscovery: ChromiumProfileDiscovery

    init(
        workspace: any WorkspaceClient = SystemWorkspaceClient(),
        profileDiscovery: ChromiumProfileDiscovery = ChromiumProfileDiscovery()
    ) {
        self.workspace = workspace
        self.profileDiscovery = profileDiscovery
    }

    func open(_ url: URL, with browser: BrowserDescriptor) async throws -> BrowserLaunchResult {
        guard browser.availability == .available,
              browser.applicationURL.isFileURL,
              FileManager.default.fileExists(atPath: browser.applicationURL.path),
              FileManager.default.isReadableFile(atPath: browser.applicationURL.path) else {
            throw BrowserLaunchError.applicationUnavailable
        }

        do {
            if let profile = browser.profile {
                guard browser.id == profile.browserID(bundleIdentifier: browser.bundleIdentifier),
                      profileDiscovery.isAvailable(profile, bundleIdentifier: browser.bundleIdentifier) else {
                    throw BrowserLaunchError.applicationUnavailable
                }
                try await workspace.openApplication(
                    at: browser.applicationURL,
                    arguments: ["--profile-directory=\(profile.directoryName)", url.absoluteString]
                )
            } else {
                try await workspace.open(url, with: browser.applicationURL)
            }
            return .handoffSucceeded
        } catch let error as BrowserLaunchError {
            throw error
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
