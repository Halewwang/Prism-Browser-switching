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

public struct ChromiumProfileDescriptor: Codable, Equatable, Sendable {
    public let directoryName: String
    public let displayName: String
    public let userDataDirectory: URL

    public init(directoryName: String, displayName: String, userDataDirectory: URL) {
        self.directoryName = directoryName
        self.displayName = displayName
        self.userDataDirectory = userDataDirectory
    }

    public func browserID(bundleIdentifier: String) -> BrowserID {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        let directory = directoryName.addingPercentEncoding(withAllowedCharacters: allowed) ?? directoryName
        return BrowserID("\(bundleIdentifier)::profile::\(directory)")
    }
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
    public let profile: ChromiumProfileDescriptor?

    public init(
        id: BrowserID,
        bundleIdentifier: String,
        displayName: String,
        applicationURL: URL,
        securityScopedBookmark: Data?,
        origin: BrowserOrigin,
        availability: BrowserAvailability,
        selectorOrder: Int,
        profile: ChromiumProfileDescriptor? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.applicationURL = applicationURL
        self.securityScopedBookmark = securityScopedBookmark
        self.origin = origin
        self.availability = availability
        self.selectorOrder = selectorOrder
        self.profile = profile
    }
}
