import AppKit
import Foundation

/// Public-test updates verify an independent update signature before installation.
@MainActor
final class GitHubUpdateChecker: UpdateChecking {
    let events: AsyncStream<UpdateEvent>
    private let continuation: AsyncStream<UpdateEvent>.Continuation
    private let currentVersion: String
    private let defaults: UserDefaults
    private let loadInstaller: @MainActor () async throws -> GitHubPublishedInstaller
    private let present: (@MainActor (UpdateEvent, GitHubPublishedInstaller?) -> Void)?
    private let startAutomatically: Bool
    private var schedule: Task<Void, Never>?
    private var check: Task<Void, Never>?
    private var manualCheckRequested = false
    private var updateWindow: InAppUpdateWindowController?
    private var preparedHelper: PreparedInstallation?
    private var prepareInstallationTermination: @MainActor () async throws -> Void = {
        throw UpdateFailureForPresentation.notReady
    }
    private var cancelInstallationTermination: @MainActor () -> Void = {}

    var hasPreparedInstallation: Bool { updateWindow?.session.hasPreparedInstallation == true }

    func setInstallationPreparation(
        prepare: @escaping @MainActor () async throws -> Void,
        cancel: @escaping @MainActor () -> Void
    ) {
        prepareInstallationTermination = prepare
        cancelInstallationTermination = cancel
    }

    func cancelPreparedInstallation(message: String) {
        updateWindow?.session.cancelPreparedInstallation(message: message)
    }

    func commitPreparedInstallation() throws {
        guard let session = updateWindow?.session else { throw UpdateFailureForPresentation.notReady }
        try session.commitPreparedInstallation()
    }

    func showUpdate(_ installer: GitHubPublishedInstaller) {
        if let window = updateWindow, window.window?.isVisible == true {
            window.present()
            return
        }
        let preparer = GitHubUpdatePackagePreparer()
        let coordinator = NativeUpdateInstallationCoordinator()
        let model = InAppUpdateSession(
            installer: installer,
            prepare: { installer, progress in try await preparer.prepare(installer, progress: progress) },
            cleanup: { preparer.cleanup($0) },
            startInstallation: { [weak self] prepared in
                let targetURL = try InstallerLaunchValidation.currentInstallationURL()
                let handle = try await coordinator.prepareInstallation(prepared, targetURL: targetURL, parentPID: ProcessInfo.processInfo.processIdentifier)
                self?.preparedHelper = handle
                return { [weak self] in handle.cancel(); self?.preparedHelper = nil }
            },
            prepareTermination: { [weak self] in
                guard let self else { throw UpdateFailureForPresentation.notReady }
                try await self.prepareInstallationTermination()
            },
            cancelTermination: { [weak self] in self?.cancelInstallationTermination() },
            terminate: { NSApp.terminate(nil) },
            commitInstallation: { [weak self] in
                guard let handle = self?.preparedHelper else { throw UpdateFailureForPresentation.notReady }
                try handle.commit()
            },
            onEvent: { [weak self] in self?.continuation.yield($0) }
        )
        let window = InAppUpdateWindowController(session: model)
        updateWindow = window
        window.present()
    }

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
        present: (@MainActor (UpdateEvent, GitHubPublishedInstaller?) -> Void)? = nil
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
                presentResult(result, installer)
            } else if wasManual {
                presentResult(result, installer)
            }
            continuation.yield(result)
        }
    }

    private func presentResult(_ result: UpdateEvent, _ installer: GitHubPublishedInstaller?) {
        if let present { present(result, installer); return }
        if case .available = result, let installer { showUpdate(installer); return }
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
        alert.runModal()
    }
}

private enum UpdateFailureForPresentation: LocalizedError {
    case notReady
    var errorDescription: String? {
        NSLocalizedString("Prism is still starting. Try installing the update again in a moment.", comment: "Update gate")
    }
}
