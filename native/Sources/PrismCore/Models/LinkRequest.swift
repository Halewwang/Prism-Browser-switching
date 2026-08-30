import Foundation

public enum SourceConfidence: String, Codable, Equatable, Sendable {
    case confirmed
    case low
    case unknown
}

public struct SourceApplication: Codable, Equatable, Sendable {
    public let bundleIdentifier: String?
    public let displayName: String
    public let confidence: SourceConfidence

    public init(bundleIdentifier: String?, displayName: String, confidence: SourceConfidence) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.confidence = confidence
    }

    public static let unknown = SourceApplication(
        bundleIdentifier: nil,
        displayName: "Unknown",
        confidence: .unknown
    )

    /// Source rules may fire only for a confirmed Apple Event attribution with a bundle ID.
    /// Low-confidence activation inference and unknown sources never count as a hit.
    public var isConfirmedForSourceRules: Bool {
        guard confidence == .confirmed else { return false }
        let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !bundleIdentifier.isEmpty
    }
}

public enum LinkRequestState: String, Codable, Equatable, Sendable {
    case queued
    case presenting
    case launching
    case outcomeUnknown
}

public struct LinkRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let receivedAt: Date
    public let source: SourceApplication
    public var state: LinkRequestState
    public var attemptCount: Int
    public var lastAttemptedBrowserID: BrowserID?
    public var reopenedFromHistoryEntryID: UUID?

    public init(
        id: UUID,
        url: URL,
        receivedAt: Date,
        source: SourceApplication,
        state: LinkRequestState = .queued,
        attemptCount: Int = 0,
        lastAttemptedBrowserID: BrowserID? = nil,
        reopenedFromHistoryEntryID: UUID? = nil
    ) {
        self.id = id
        self.url = url
        self.receivedAt = receivedAt
        self.source = source
        self.state = state
        self.attemptCount = attemptCount
        self.lastAttemptedBrowserID = lastAttemptedBrowserID
        self.reopenedFromHistoryEntryID = reopenedFromHistoryEntryID
    }
}

public enum TerminalRequestOutcome: String, Codable, Equatable, Sendable {
    case succeeded
    case cancelled
}

public struct TerminalRequestRecord: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let outcome: TerminalRequestOutcome
    public let historyEntry: HistoryEntry?
    public let completedAt: Date

    public init(
        requestID: UUID,
        outcome: TerminalRequestOutcome,
        historyEntry: HistoryEntry?,
        completedAt: Date
    ) {
        self.requestID = requestID
        self.outcome = outcome
        self.historyEntry = historyEntry
        self.completedAt = completedAt
    }
}

public struct PendingRequestSnapshot: Codable, Equatable, Sendable {
    public var pendingRequests: [LinkRequest]
    public var terminalRecords: [TerminalRequestRecord]

    public init(pendingRequests: [LinkRequest], terminalRecords: [TerminalRequestRecord]) {
        self.pendingRequests = pendingRequests
        self.terminalRecords = terminalRecords
    }
}
