import Foundation

public enum RuleMatcher: Codable, Equatable, Sendable {
    case exactHost(String)
    case hostAndSubdomains(String)
    case urlContains(String)
    case sourceBundleIdentifier(String)
}

public enum RuleValidationState: String, Codable, Equatable, Sendable {
    case valid
    case targetUnavailable
    case sourceIneligible
}

public struct RoutingRule: Codable, Equatable, Sendable {
    public let id: UUID
    public var isEnabled: Bool
    public var matcher: RuleMatcher
    public var targetBrowserID: BrowserID
    public var priority: Int
    public var label: String?
    public var validationState: RuleValidationState
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        isEnabled: Bool,
        matcher: RuleMatcher,
        targetBrowserID: BrowserID,
        priority: Int,
        label: String?,
        validationState: RuleValidationState = .valid,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.matcher = matcher
        self.targetBrowserID = targetBrowserID
        self.priority = priority
        self.label = label
        self.validationState = validationState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
