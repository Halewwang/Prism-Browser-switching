import Foundation

public struct BrowserID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public enum BrowserOrigin: String, Codable, Equatable, Sendable {
    case system
    case custom
}

public enum BrowserAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
}

public struct BrowserDescriptor: Codable, Equatable, Sendable {
    public let id: BrowserID
    public let bundleIdentifier: String
    public let displayName: String
    public let applicationURL: URL
    public let securityScopedBookmark: Data?
    public let origin: BrowserOrigin
    public let availability: BrowserAvailability
    public let selectorOrder: Int

    public init(
        id: BrowserID,
        bundleIdentifier: String,
        displayName: String,
        applicationURL: URL,
        securityScopedBookmark: Data?,
        origin: BrowserOrigin,
        availability: BrowserAvailability,
        selectorOrder: Int
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.applicationURL = applicationURL
        self.securityScopedBookmark = securityScopedBookmark
        self.origin = origin
        self.availability = availability
        self.selectorOrder = selectorOrder
    }
}
