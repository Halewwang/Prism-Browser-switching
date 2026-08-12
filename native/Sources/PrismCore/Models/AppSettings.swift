import Foundation

public enum UnmatchedBehavior: String, Codable, Equatable, Sendable {
    case alwaysAsk
    case preferredBrowser
    case lastUsedBrowser
}

public enum AppLanguage: String, Codable, Equatable, Sendable {
    case system
    case english
    case simplifiedChinese
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var language: AppLanguage
    public var unmatchedBehavior: UnmatchedBehavior
    public var preferredBrowserID: BrowserID?
    public var lastUsedBrowserID: BrowserID?
    public var historyEnabled: Bool
    public var historyLimit: Int
    public var historyRetentionDays: Int
    public var automaticRulesEnabled: Bool
    public var showMenuBarItem: Bool
    public var onboardingCompleted: Bool
    public var schemaVersion: Int

    public init(
        language: AppLanguage,
        unmatchedBehavior: UnmatchedBehavior,
        preferredBrowserID: BrowserID?,
        lastUsedBrowserID: BrowserID?,
        historyEnabled: Bool,
        historyLimit: Int,
        historyRetentionDays: Int,
        automaticRulesEnabled: Bool,
        showMenuBarItem: Bool,
        onboardingCompleted: Bool,
        schemaVersion: Int
    ) {
        self.language = language
        self.unmatchedBehavior = unmatchedBehavior
        self.preferredBrowserID = preferredBrowserID
        self.lastUsedBrowserID = lastUsedBrowserID
        self.historyEnabled = historyEnabled
        self.historyLimit = historyLimit
        self.historyRetentionDays = historyRetentionDays
        self.automaticRulesEnabled = automaticRulesEnabled
        self.showMenuBarItem = showMenuBarItem
        self.onboardingCompleted = onboardingCompleted
        self.schemaVersion = schemaVersion
    }

    public static let defaults = AppSettings(
        language: .system,
        unmatchedBehavior: .alwaysAsk,
        preferredBrowserID: nil,
        lastUsedBrowserID: nil,
        historyEnabled: true,
        historyLimit: 100,
        historyRetentionDays: 30,
        automaticRulesEnabled: true,
        showMenuBarItem: true,
        onboardingCompleted: false,
        schemaVersion: 1
    )
}
