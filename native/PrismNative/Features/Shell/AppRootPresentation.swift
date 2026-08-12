import SwiftUI

enum RuntimeLinkRecoveryState: Equatable, Sendable {
    case none
    case persistenceRetryRequired
    case routingResumeRequired

    init(_ intakeState: LinkIntakeService.RecoveryState) {
        switch intakeState {
        case .none:
            self = .none
        case .persistenceRetryRequired:
            self = .persistenceRetryRequired
        case .routingResumeRequired:
            self = .routingResumeRequired
        }
    }
}

enum AppRootKind: Equatable, Sendable {
    case loading
    case onboarding
    case shell
    case recovery

    init(startupPhase: AppStartupPhase) {
        switch startupPhase {
        case .loading:
            self = .loading
        case .onboarding:
            self = .onboarding
        case .shell:
            self = .shell
        case .recovery:
            self = .recovery
        }
    }
}

enum AppRecoveryAction: String, Equatable, Sendable {
    case retryHistory
    case retryRestoration
    case retryPendingPersistence
    case resumeRouting
    case restart
}

enum AppRecoveryReason: Equatable, Sendable {
    case pendingTerminalHistory
    case startupRestoration
    case runtimePendingPersistence
    case runtimeRoutingPaused
    case runtimeStorageUnavailable
    case historyNotSaved
    case settingsNotSaved
    case corruptStoreRecovered(backupLocation: String)
}

struct AppRecoveryActionPresentation: Equatable, Sendable {
    let action: AppRecoveryAction
    let title: String
    let accessibilityIdentifier: String
}

struct AppRecoveryPresentation: Equatable, Sendable {
    let reason: AppRecoveryReason
    let title: String
    let message: String
    let primaryAction: AppRecoveryActionPresentation

    var actions: [AppRecoveryActionPresentation] {
        [primaryAction]
    }
}

struct AppRootPresentation: Equatable, Sendable {
    let kind: AppRootKind
    let recovery: AppRecoveryPresentation?

    init(
        startupPhase: AppStartupPhase,
        hasPendingTerminalHistoryReconciliation: Bool,
        runtimeLinkRecoveryState: RuntimeLinkRecoveryState = .none,
        persistenceWarnings: [PersistenceWarning]
    ) {
        kind = AppRootKind(startupPhase: startupPhase)
        recovery = Self.makeRecovery(
            startupPhase: startupPhase,
            hasPendingTerminalHistoryReconciliation: hasPendingTerminalHistoryReconciliation,
            runtimeLinkRecoveryState: runtimeLinkRecoveryState,
            persistenceWarnings: persistenceWarnings
        )
    }

    private static func makeRecovery(
        startupPhase: AppStartupPhase,
        hasPendingTerminalHistoryReconciliation: Bool,
        runtimeLinkRecoveryState: RuntimeLinkRecoveryState,
        persistenceWarnings: [PersistenceWarning]
    ) -> AppRecoveryPresentation? {
        if runtimeLinkRecoveryState == .persistenceRetryRequired {
            return AppRecoveryPresentation(
                reason: .runtimePendingPersistence,
                title: "A link is waiting to be saved",
                message: "Prism kept the link safely. Retry saving before link handling resumes.",
                primaryAction: AppRecoveryActionPresentation(
                    action: .retryPendingPersistence,
                    title: "Retry Saving Link",
                    accessibilityIdentifier: "recovery.persistence.retry"
                )
            )
        }

        if hasPendingTerminalHistoryReconciliation {
            return AppRecoveryPresentation(
                reason: .pendingTerminalHistory,
                title: "History is waiting to be saved",
                message: "Prism kept the completed link safely. Retry when storage is available.",
                primaryAction: AppRecoveryActionPresentation(
                    action: .retryHistory,
                    title: "Retry History",
                    accessibilityIdentifier: "recovery.history.retry"
                )
            )
        }

        if startupPhase == .recovery {
            return AppRecoveryPresentation(
                reason: .startupRestoration,
                title: "Prism could not restore pending links",
                message: "Retry before Prism resumes handling links.",
                primaryAction: AppRecoveryActionPresentation(
                    action: .retryRestoration,
                    title: "Retry",
                    accessibilityIdentifier: "recovery.restoration.retry"
                )
            )
        }

        if runtimeLinkRecoveryState == .routingResumeRequired {
            return AppRecoveryPresentation(
                reason: .runtimeRoutingPaused,
                title: "Link handling is paused",
                message: "Pending links are saved and ready when you choose to continue.",
                primaryAction: AppRecoveryActionPresentation(
                    action: .resumeRouting,
                    title: "Resume Link Handling",
                    accessibilityIdentifier: "recovery.routing.resume"
                )
            )
        }

        if persistenceWarnings.contains(.recoveryStoreUnavailable) {
            return restartPresentation(
                reason: .runtimeStorageUnavailable,
                title: "Prism storage is unavailable",
                message: "Restart Prism before handling more links."
            )
        }

        if let corruptStoreWarning = persistenceWarnings.first(where: { warning in
            if case .corruptStoreRecovered = warning { return true }
            return false
        }), case let .corruptStoreRecovered(backupLocation) = corruptStoreWarning {
            return restartPresentation(
                reason: .corruptStoreRecovered(backupLocation: backupLocation),
                title: "Prism recovered damaged data",
                message: "Restart Prism before continuing."
            )
        }

        if persistenceWarnings.contains(.settingsNotSaved) {
            return restartPresentation(
                reason: .settingsNotSaved,
                title: "Your settings could not be saved",
                message: "Restart Prism before changing more settings."
            )
        }

        if persistenceWarnings.contains(.historyNotSaved) {
            return restartPresentation(
                reason: .historyNotSaved,
                title: "History could not be saved",
                message: "This is not a pending History reconciliation. Restart Prism before continuing."
            )
        }

        return nil
    }

    private static func restartPresentation(
        reason: AppRecoveryReason,
        title: String,
        message: String
    ) -> AppRecoveryPresentation {
        AppRecoveryPresentation(
            reason: reason,
            title: title,
            message: message,
            primaryAction: AppRecoveryActionPresentation(
                action: .restart,
                title: "Restart Prism",
                accessibilityIdentifier: "recovery.restart"
            )
        )
    }
}

@MainActor
extension AppEnvironment {
    var sharedRouteBinding: Binding<AppRoute> {
        Binding(
            get: { self.route },
            set: { self.updateRoute($0) }
        )
    }
}
