import AppKit
import PrismCore

@MainActor
protocol ApplicationActivationObserving: AnyObject {
    func observeActivations(_ handler: @escaping @MainActor @Sendable (SourceApplication?) -> Void) -> NSObjectProtocol
    func removeObserver(_ observer: NSObjectProtocol)
}

@MainActor
final class ApplicationActivationTracker {
    private let observer: any ApplicationActivationObserving
    private let prismBundleIdentifier: String
    private var observerToken: NSObjectProtocol?
    private(set) var lastActivatedApplication: SourceApplication?

    init(
        observer: any ApplicationActivationObserving = WorkspaceApplicationActivationObserver(),
        prismBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.prism.app"
    ) {
        self.observer = observer
        self.prismBundleIdentifier = prismBundleIdentifier
        observerToken = observer.observeActivations { [weak self] application in
            self?.recordActivation(application)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let observerToken {
                observer.removeObserver(observerToken)
            }
        }
    }

    func stop() {
        guard let observerToken else { return }
        observer.removeObserver(observerToken)
        self.observerToken = nil
    }

    private func recordActivation(_ application: SourceApplication?) {
        guard let application,
              let bundleIdentifier = usableActivationBundleIdentifier(application.bundleIdentifier),
              bundleIdentifier != prismBundleIdentifier
        else {
            return
        }

        lastActivatedApplication = SourceApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: usableActivationDisplayName(application.displayName) ?? bundleIdentifier,
            confidence: .unknown
        )
    }
}

@MainActor
private final class WorkspaceApplicationActivationObserver: ApplicationActivationObserving {
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter

    init(
        workspace: NSWorkspace = .shared,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.workspace = workspace
        self.notificationCenter = notificationCenter
    }

    func observeActivations(_ handler: @escaping @MainActor @Sendable (SourceApplication?) -> Void) -> NSObjectProtocol {
        notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: workspace,
            queue: .main
        ) { [handler] notification in
            let source: SourceApplication?
            if let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                let bundleIdentifier = application.bundleIdentifier
                let displayName = application.localizedName ?? bundleIdentifier ?? "Unknown"
                source = SourceApplication(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    confidence: .unknown
                )
            } else {
                source = nil
            }

            Task { @MainActor in
                handler(source)
            }
        }
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        notificationCenter.removeObserver(observer)
    }
}

private func usableActivationBundleIdentifier(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func usableActivationDisplayName(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
