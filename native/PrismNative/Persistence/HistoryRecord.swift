import Foundation
import PrismCore
import SwiftData

@Model
final class HistoryRecord {
    @Attribute(.unique) var id: UUID
    var requestID: UUID
    var sanitizedURLString: String?
    var sourceBundleIdentifier: String?
    var sourceDisplayName: String
    var targetBrowserID: String?
    var targetDisplayName: String?
    var method: String?
    var result: String
    var matchingRuleID: UUID?
    var failureReason: String?
    var attemptCount: Int
    var createdAt: Date
    var completedAt: Date?

    init(entry: HistoryEntry, sanitizer: URLSanitizer = .default) {
        id = entry.id
        requestID = entry.requestID
        sanitizedURLString = entry.sanitizedURL.flatMap { sanitizer.sanitize($0)?.absoluteString }
        sourceBundleIdentifier = entry.sourceBundleIdentifier
        sourceDisplayName = entry.sourceDisplayName
        targetBrowserID = entry.targetBrowserID?.rawValue
        targetDisplayName = entry.targetDisplayName
        method = entry.method?.rawValue
        result = entry.result.rawValue
        matchingRuleID = entry.matchingRuleID
        failureReason = Self.persistedFailureReason(from: entry.failureReason)
        attemptCount = entry.attemptCount
        createdAt = entry.createdAt
        completedAt = entry.completedAt
    }

    func historyEntry() throws -> HistoryEntry {
        guard let result = HistoryResult(rawValue: result) else {
            throw PersistenceRecordError.invalidPayload
        }
        guard method == nil || RoutingMethod(rawValue: method!) != nil else {
            throw PersistenceRecordError.invalidPayload
        }

        return HistoryEntry(
            id: id,
            requestID: requestID,
            sanitizedURL: sanitizedURLString.flatMap(URL.init(string:)),
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceDisplayName: sourceDisplayName,
            targetBrowserID: targetBrowserID.map(BrowserID.init(rawValue:)),
            targetDisplayName: targetDisplayName,
            method: method.flatMap(RoutingMethod.init(rawValue:)),
            result: result,
            matchingRuleID: matchingRuleID,
            failureReason: failureReason,
            attemptCount: attemptCount,
            createdAt: createdAt,
            completedAt: completedAt
        )
    }

    func replace(with entry: HistoryEntry, sanitizer: URLSanitizer = .default) {
        requestID = entry.requestID
        sanitizedURLString = entry.sanitizedURL.flatMap { sanitizer.sanitize($0)?.absoluteString }
        sourceBundleIdentifier = entry.sourceBundleIdentifier
        sourceDisplayName = entry.sourceDisplayName
        targetBrowserID = entry.targetBrowserID?.rawValue
        targetDisplayName = entry.targetDisplayName
        method = entry.method?.rawValue
        result = entry.result.rawValue
        matchingRuleID = entry.matchingRuleID
        failureReason = Self.persistedFailureReason(from: entry.failureReason)
        attemptCount = entry.attemptCount
        createdAt = entry.createdAt
        completedAt = entry.completedAt
    }

    private static func persistedFailureReason(from failureReason: String?) -> String? {
        guard let failureReason, !failureReason.isEmpty else { return nil }
        return "launch_failed"
    }
}
