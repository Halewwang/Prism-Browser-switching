import AppKit
import Foundation

/// Unsigned builds can check releases, but installation remains a user action.
@MainActor
final class GitHubUpdateChecker: UpdateChecking {
    let events: AsyncStream<UpdateEvent>
    private let continuation: AsyncStream<UpdateEvent>.Continuation
    private let currentVersion: String
    private let defaults: UserDefaults
    private let loadInstaller: @MainActor () async throws -> GitHubPublishedInstaller
    private let present: @MainActor (UpdateEvent, GitHubPublishedInstaller?) -> Void
    private let startAutomatically: Bool
    private var schedule: Task<Void, Never>?
    private var check: Task<Void, Never>?
    private var manualCheckRequested = false

    static let lastCheckKey = "PrismGitHubLastUpdateCheck"
    private static let lastNotifiedKey = "PrismGitHubLastNotifiedVersion"
    private static let interval: TimeInterval = 24 * 60 * 60

    // Keep the action visible while a check is running; repeated clicks join it.
    let canCheckForUpdates = true
    var automaticallyChecksForUpdates: Bool {
        get { defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "SUEnableAutomaticChecks")
            scheduleAutomaticChecks()
        }
    }

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
        defaults: UserDefaults = .standard,
        startAutomatically: Bool = true,
        loadInstaller: @escaping @MainActor () async throws -> GitHubPublishedInstaller = { try await GitHubPublishedInstallerLookup.load() },
        present: @escaping @MainActor (UpdateEvent, GitHubPublishedInstaller?) -> Void = GitHubUpdateChecker.presentResult
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.startAutomatically = startAutomatically
        self.loadInstaller = loadInstaller
        self.present = present
        (events, continuation) = AsyncStream.makeStream()
        scheduleAutomaticChecks()
    }

    deinit {
        schedule?.cancel()
        check?.cancel()
        continuation.finish()
    }

    func checkForUpdates() {
        manualCheckRequested = true
        beginCheck()
    }

    func checkAutomaticallyIfDue(now: Date = Date()) {
        let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard automaticallyChecksForUpdates,
              now < lastCheck || now.timeIntervalSince(lastCheck) >= Self.interval
        else { return }
        beginCheck()
    }

    private func scheduleAutomaticChecks() {
        schedule?.cancel()
        schedule = nil
        guard startAutomatically, automaticallyChecksForUpdates else { return }
        schedule = Task { [weak self] in
            // Give startup and link restoration time to finish before contacting GitHub.
            do {
                try await Task.sleep(for: .seconds(10))
                while !Task.isCancelled {
                    self?.checkAutomaticallyIfDue()
                    try await Task.sleep(for: .seconds(60 * 60))
                }
            } catch { /* Turning off automatic checks cancels this schedule. */ }
        }
    }

    private func beginCheck() {
        guard check == nil else { return }
        continuation.yield(.checking)
        check = Task { [weak self] in
            guard let self else { return }
            var installer: GitHubPublishedInstaller?
            let result: UpdateEvent
            do {
                let release = try await loadInstaller()
                installer = release
                if let newer = GitHubPublishedInstaller.isNewer(release.version, than: currentVersion) {
                    result = newer ? .available(version: release.version) : .current
                } else {
                    result = .failed(.configuration)
                }
            } catch GitHubPublishedInstallerError.noCompatibleRelease {
                result = .failed(.system(NSLocalizedString("No compatible native installer is published on GitHub yet.", comment: "Update check")))
            } catch {
                result = .failed(.network)
            }
            defaults.set(Date(), forKey: Self.lastCheckKey)
            let wasManual = manualCheckRequested
            manualCheckRequested = false
            check = nil
            if case let .available(version) = result,
               wasManual || (automaticallyChecksForUpdates && defaults.string(forKey: Self.lastNotifiedKey) != version) {
                defaults.set(version, forKey: Self.lastNotifiedKey)
                present(result, installer)
            } else if wasManual {
                present(result, installer)
            }
            continuation.yield(result)
        }
    }

    private static func presentResult(_ result: UpdateEvent, _ installer: GitHubPublishedInstaller?) {
        let alert = NSAlert()
        switch result {
        case .available:
            guard let installer else { return }
            let title = installer.isPrerelease ? "Prism %@ public test is available" : "Prism %@ is available"
            alert.messageText = String(format: NSLocalizedString(title, comment: "Update alert title"), installer.version)
            alert.informativeText = NSLocalizedString("Download the installer from GitHub, then replace Prism in Applications to update.", comment: "Update alert")
            alert.addButton(withTitle: NSLocalizedString("Download installer", comment: "Update action"))
            alert.addButton(withTitle: NSLocalizedString("Later", comment: "Update action"))
        case .current:
            alert.messageText = NSLocalizedString("Prism is up to date", comment: "Update alert title")
            alert.informativeText = NSLocalizedString("You have the latest published native version of Prism.", comment: "Update alert")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Update action"))
        case let .failed(reason):
            alert.alertStyle = .warning
            alert.messageText = NSLocalizedString("Could not check for updates", comment: "Update alert title")
            if case let .system(message) = reason {
                alert.informativeText = message
            } else if reason == .configuration {
                alert.informativeText = NSLocalizedString("Prism could not read this app's version. Open GitHub Releases to check manually.", comment: "Update alert")
            } else {
                alert.informativeText = NSLocalizedString("Prism could not reach GitHub. Check your connection and try again.", comment: "Update alert")
            }
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Update action"))
        default:
            return
        }
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, case .available = result, let installer {
            NSWorkspace.shared.open(installer.downloadURL)
        }
    }
}
