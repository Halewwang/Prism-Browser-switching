import Foundation
import Sparkle

/// Bridges Prism's small update boundary to Sparkle's maintained standard updater UI.
/// Builds without a real public EdDSA key check GitHub for manual installers.
@MainActor
final class SparkleUpdateChecker: NSObject, UpdateChecking {
    let events: AsyncStream<UpdateEvent>
    private let continuation: AsyncStream<UpdateEvent>.Continuation
    private let controller: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    init(controller: SPUStandardUpdaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )) {
        self.controller = controller
        var streamContinuation: AsyncStream<UpdateEvent>.Continuation?
        events = AsyncStream { streamContinuation = $0 }
        continuation = streamContinuation!
    }

    func checkForUpdates() {
        guard canCheckForUpdates else {
            continuation.yield(.failed(.configuration))
            return
        }
        continuation.yield(.checking)
        controller.checkForUpdates(nil)
    }

    static func makeIfConfigured(bundle: Bundle = .main) -> any UpdateChecking {
        guard SparkleUpdateConfiguration(bundle: bundle).isReady else {
            return GitHubUpdateChecker(
                currentVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
            )
        }
        return SparkleUpdateChecker()
    }
}

struct SparkleUpdateConfiguration: Equatable {
    let feedURL: URL?
    let publicEDKey: String?

    init(bundle: Bundle = .main) {
        let feedValue = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        feedURL = feedValue.flatMap(URL.init(string:))
        publicEDKey = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(feedURL: URL?, publicEDKey: String?) {
        self.feedURL = feedURL
        self.publicEDKey = publicEDKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isReady: Bool {
        guard feedURL?.scheme?.lowercased() == "https",
              let publicEDKey,
              !publicEDKey.isEmpty
        else { return false }
        return !publicEDKey.hasPrefix("$(")
    }
}
