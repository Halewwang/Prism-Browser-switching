import AppKit
import Foundation

enum DefaultHandlerState: Equatable, Sendable {
    case active
    case inactive(http: Bool, https: Bool)
}

enum DefaultBrowserServiceError: Error, Equatable {
    case incomplete(state: DefaultHandlerState, failedSchemes: [String])
}

@MainActor
protocol DefaultHandlerClient: AnyObject {
    func handlerBundleIdentifier(forScheme scheme: String) -> String?
    func setDefault(applicationURL: URL, forScheme scheme: String) async throws
}

@MainActor
final class DefaultBrowserService {
    private static let schemes = ["http", "https"]

    private let client: any DefaultHandlerClient
    private let applicationURL: URL
    private let bundleIdentifier: String

    init(
        client: any DefaultHandlerClient = SystemDefaultHandlerClient(),
        applicationURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.prism.app"
    ) {
        self.client = client
        self.applicationURL = applicationURL
        self.bundleIdentifier = bundleIdentifier
    }

    func status() async throws -> DefaultHandlerState {
        currentState()
    }

    func setAsDefaultAfterUserConfirmation() async throws -> DefaultHandlerState {
        var failedSchemes: [String] = []

        for scheme in Self.schemes {
            do {
                try await client.setDefault(applicationURL: applicationURL, forScheme: scheme)
            } catch {
                failedSchemes.append(scheme)
            }
        }

        let state = currentState()
        guard failedSchemes.isEmpty, state == .active else {
            throw DefaultBrowserServiceError.incomplete(
                state: state,
                failedSchemes: failedSchemes
            )
        }
        return state
    }

    private func currentState() -> DefaultHandlerState {
        let http = client.handlerBundleIdentifier(forScheme: "http") == bundleIdentifier
        let https = client.handlerBundleIdentifier(forScheme: "https") == bundleIdentifier
        return http && https ? .active : .inactive(http: http, https: https)
    }
}

@MainActor
final class SystemDefaultHandlerClient: DefaultHandlerClient {
    private static let probes = [
        "http": URL(string: "http://example.com")!,
        "https": URL(string: "https://example.com")!
    ]

    func handlerBundleIdentifier(forScheme scheme: String) -> String? {
        guard let probeURL = Self.probes[scheme],
              let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL)
        else {
            return nil
        }
        return Bundle(url: applicationURL)?.bundleIdentifier
    }

    func setDefault(applicationURL: URL, forScheme scheme: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(
                at: applicationURL,
                toOpenURLsWithScheme: scheme
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
