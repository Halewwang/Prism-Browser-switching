import Foundation
@testable import PrismCore

extension LinkRequest {
    static func fixture(
        id: UUID = UUID(uuidString: "A4C3CB34-05C4-4B06-83EB-D18CE0260F63")!,
        url: String = "https://example.com",
        sourceBundleID: String? = nil,
        confidence: SourceConfidence = .unknown
    ) -> LinkRequest {
        LinkRequest(
            id: id,
            url: URL(string: url)!,
            receivedAt: Date(timeIntervalSince1970: 1),
            source: SourceApplication(
                bundleIdentifier: sourceBundleID,
                displayName: sourceBundleID ?? "Unknown",
                confidence: confidence
            )
        )
    }
}

extension RoutingRule {
    static func fixture(
        id: UUID = UUID(uuidString: "9EA80967-70C1-4BCE-BC6C-C79754C168F2")!,
        matcher: RuleMatcher,
        browser: BrowserID,
        priority: Int
    ) -> RoutingRule {
        RoutingRule(
            id: id,
            isEnabled: true,
            matcher: matcher,
            targetBrowserID: browser,
            priority: priority,
            label: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }
}

extension HistoryEntry {
    static func fixture(
        requestID: UUID = .test(1),
        result: HistoryResult = .cancelled,
        sanitizedURL: String? = "https://example.com"
    ) -> HistoryEntry {
        HistoryEntry(
            id: .test(2),
            requestID: requestID,
            sanitizedURL: sanitizedURL.flatMap(URL.init(string:)),
            sourceBundleIdentifier: nil,
            sourceDisplayName: "Unknown",
            targetBrowserID: nil,
            targetDisplayName: nil,
            method: nil,
            result: result,
            matchingRuleID: nil,
            failureReason: nil,
            attemptCount: 0,
            createdAt: Date(timeIntervalSince1970: 1),
            completedAt: result == .processing ? nil : Date(timeIntervalSince1970: 2)
        )
    }

    static var cancelledFixture: HistoryEntry {
        fixture(result: .cancelled)
    }
}

extension UUID {
    static func test(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
