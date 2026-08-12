import AppKit
import PrismCore

@MainActor
protocol SourceAttributing {
    func resolve(senderPID: Int32?, lastActivated: SourceApplication?) -> SourceApplication
}

@MainActor
protocol RunningApplicationLookup {
    func sourceApplication(processIdentifier: Int32) -> SourceApplication?
}

struct RunningApplicationSnapshot: Equatable, Sendable {
    let bundleIdentifier: String?
    let displayName: String?
    let isActive: Bool
    let isTerminated: Bool
}

@MainActor
protocol RunningApplicationInspecting {
    func snapshot(processIdentifier: Int32) -> RunningApplicationSnapshot?
}

@MainActor
final class SystemRunningApplicationLookup: RunningApplicationLookup {
    private let inspector: any RunningApplicationInspecting

    init(inspector: any RunningApplicationInspecting = NSRunningApplicationInspector()) {
        self.inspector = inspector
    }

    func sourceApplication(processIdentifier: Int32) -> SourceApplication? {
        guard processIdentifier > 0,
              let snapshot = inspector.snapshot(processIdentifier: processIdentifier),
              snapshot.isActive,
              !snapshot.isTerminated,
              let bundleIdentifier = usableBundleIdentifier(snapshot.bundleIdentifier)
        else {
            return nil
        }

        let displayName = usableDisplayName(snapshot.displayName) ?? bundleIdentifier
        return SourceApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            confidence: .unknown
        )
    }
}

@MainActor
final class SourceAttributionProvider: SourceAttributing {
    private let runningApplications: any RunningApplicationLookup
    private let prismBundleIdentifier: String

    init(
        runningApplications: any RunningApplicationLookup = SystemRunningApplicationLookup(),
        prismBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.prism.app"
    ) {
        self.runningApplications = runningApplications
        self.prismBundleIdentifier = prismBundleIdentifier
    }

    func resolve(senderPID: Int32?, lastActivated: SourceApplication?) -> SourceApplication {
        if let senderPID {
            guard let candidate = runningApplications.sourceApplication(processIdentifier: senderPID),
                  let confirmed = confirmedSource(from: candidate)
            else {
                return .unknown
            }

            return confirmed
        }

        guard let lastActivated, let inferred = inferredSource(from: lastActivated) else {
            return .unknown
        }

        return inferred
    }

    private func confirmedSource(from candidate: SourceApplication) -> SourceApplication? {
        guard let bundleIdentifier = usableNonPrismBundleIdentifier(candidate.bundleIdentifier) else {
            return nil
        }

        return SourceApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: usableDisplayName(candidate.displayName) ?? bundleIdentifier,
            confidence: .confirmed
        )
    }

    private func inferredSource(from candidate: SourceApplication) -> SourceApplication? {
        guard let bundleIdentifier = usableNonPrismBundleIdentifier(candidate.bundleIdentifier) else {
            return nil
        }

        return SourceApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: usableDisplayName(candidate.displayName) ?? bundleIdentifier,
            confidence: .low
        )
    }

    private func usableNonPrismBundleIdentifier(_ value: String?) -> String? {
        guard let bundleIdentifier = usableBundleIdentifier(value), bundleIdentifier != prismBundleIdentifier else {
            return nil
        }

        return bundleIdentifier
    }
}

@MainActor
private final class NSRunningApplicationInspector: RunningApplicationInspecting {
    func snapshot(processIdentifier: Int32) -> RunningApplicationSnapshot? {
        guard let application = NSRunningApplication(processIdentifier: pid_t(processIdentifier)) else {
            return nil
        }

        return RunningApplicationSnapshot(
            bundleIdentifier: application.bundleIdentifier,
            displayName: application.localizedName,
            isActive: application.isActive,
            isTerminated: application.isTerminated
        )
    }
}

private func usableBundleIdentifier(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func usableDisplayName(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
