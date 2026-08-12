import Foundation

public enum RoutingMethod: String, Codable, Equatable, Sendable {
    case urlRule
    case sourceRule
    case manual
    case preferredBrowser
    case lastUsedBrowser
}

public enum HistoryResult: String, Codable, Equatable, Sendable {
    case processing
    case success
    case failure
    case cancelled
}

public struct HistoryEntry: Codable, Equatable, Sendable {
    public let id: UUID
    public let requestID: UUID
    public var sanitizedURL: URL?
    public let sourceBundleIdentifier: String?
    public let sourceDisplayName: String
    public var targetBrowserID: BrowserID?
    public var targetDisplayName: String?
    public var method: RoutingMethod?
    public var result: HistoryResult
    public var matchingRuleID: UUID?
    public var failureReason: String?
    public var attemptCount: Int
    public let createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID,
        requestID: UUID,
        sanitizedURL: URL?,
        sourceBundleIdentifier: String?,
        sourceDisplayName: String,
        targetBrowserID: BrowserID?,
        targetDisplayName: String?,
        method: RoutingMethod?,
        result: HistoryResult,
        matchingRuleID: UUID?,
        failureReason: String?,
        attemptCount: Int,
        createdAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.requestID = requestID
        self.sanitizedURL = sanitizedURL
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceDisplayName = sourceDisplayName
        self.targetBrowserID = targetBrowserID
        self.targetDisplayName = targetDisplayName
        self.method = method
        self.result = result
        self.matchingRuleID = matchingRuleID
        self.failureReason = failureReason
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    public static func processing(request: LinkRequest, sanitizedURL: URL?) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            requestID: request.id,
            sanitizedURL: sanitizedURL,
            sourceBundleIdentifier: request.source.bundleIdentifier,
            sourceDisplayName: request.source.displayName,
            targetBrowserID: nil,
            targetDisplayName: nil,
            method: nil,
            result: .processing,
            matchingRuleID: nil,
            failureReason: nil,
            attemptCount: request.attemptCount,
            createdAt: request.receivedAt,
            completedAt: nil
        )
    }
}
