import AppKit
import Darwin
import PrismCore

@MainActor
protocol SourceAttributing {
    func resolve(senderPID: Int32?, lastActivated: SourceApplication?) -> SourceApplication
}

@MainActor
protocol RunningApplicationLookup {
    func sourceApplication(processIdentifier: Int32) -> SourceApplication?
}

@MainActor
protocol ProcessAncestryProviding {
    func parentProcessIdentifier(of processIdentifier: Int32) -> Int32?
}

struct EmptyProcessAncestry: ProcessAncestryProviding {
    func parentProcessIdentifier(of processIdentifier: Int32) -> Int32? { nil }
}

struct SystemProcessAncestry: ProcessAncestryProviding {
    func parentProcessIdentifier(of processIdentifier: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let actualSize = proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &info, expectedSize)
        guard actualSize == expectedSize else { return nil }
        guard info.pbi_ppid > 0, info.pbi_ppid <= UInt32(Int32.max) else { return nil }
        let parent = Int32(info.pbi_ppid)
        guard parent != processIdentifier else { return nil }
        return parent
    }
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
    private let processAncestry: any ProcessAncestryProviding
    private let prismBundleIdentifier: String

    init(
        runningApplications: any RunningApplicationLookup = SystemRunningApplicationLookup(),
        processAncestry: any ProcessAncestryProviding = EmptyProcessAncestry(),
        prismBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.prism.app"
    ) {
        self.runningApplications = runningApplications
        self.processAncestry = processAncestry
        self.prismBundleIdentifier = prismBundleIdentifier
    }

    func resolve(senderPID: Int32?, lastActivated: SourceApplication?) -> SourceApplication {
        if let senderPID {
            guard let confirmed = confirmedSource(startingAt: senderPID) else {
                return .unknown
            }

            return confirmed
        }

        guard let lastActivated, let inferred = inferredSource(from: lastActivated) else {
            return .unknown
        }

        return inferred
    }

    private func confirmedSource(startingAt processIdentifier: Int32) -> SourceApplication? {
        var current: Int32? = processIdentifier
        var seen: Set<Int32> = []
        var helperFallback: SourceApplication?
        while let pid = current, pid > 0, seen.insert(pid).inserted, seen.count <= 8 {
            if let candidate = runningApplications.sourceApplication(processIdentifier: pid) {
                if let host = hostApplication(from: candidate) {
                    return host
                }
                if helperFallback == nil, let fallback = helperFallbackApplication(from: candidate) {
                    helperFallback = fallback
                }
            }
            current = processAncestry.parentProcessIdentifier(of: pid)
        }
        return helperFallback
    }

    private func hostApplication(from candidate: SourceApplication) -> SourceApplication? {
        guard let bundleIdentifier = usableNonPrismBundleIdentifier(candidate.bundleIdentifier),
              !SourceBundleIdentity.isHelper(bundleIdentifier),
              let canonical = SourceBundleIdentity.canonical(bundleIdentifier)
        else {
            return nil
        }

        return SourceApplication(
            bundleIdentifier: canonical,
            displayName: usableDisplayName(candidate.displayName) ?? canonical,
            confidence: .confirmed
        )
    }

    private func helperFallbackApplication(from candidate: SourceApplication) -> SourceApplication? {
        guard let bundleIdentifier = usableNonPrismBundleIdentifier(candidate.bundleIdentifier),
              SourceBundleIdentity.isHelper(bundleIdentifier),
              let canonical = SourceBundleIdentity.canonical(bundleIdentifier)
        else {
            return nil
        }

        return SourceApplication(
            bundleIdentifier: canonical,
            displayName: usableDisplayName(candidate.displayName) ?? canonical,
            confidence: .confirmed
        )
    }

    private func inferredSource(from candidate: SourceApplication) -> SourceApplication? {
        guard let bundleIdentifier = usableNonPrismBundleIdentifier(candidate.bundleIdentifier),
              let canonical = SourceBundleIdentity.canonical(bundleIdentifier)
        else {
            return nil
        }

        return SourceApplication(
            bundleIdentifier: canonical,
            displayName: usableDisplayName(candidate.displayName) ?? canonical,
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
