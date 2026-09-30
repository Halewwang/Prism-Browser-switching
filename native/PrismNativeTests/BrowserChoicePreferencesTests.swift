import AppKit
import Foundation
import PrismCore
import SwiftData
import Testing
@testable import PrismNative

@Suite("Browser choice preferences")
@MainActor
struct BrowserChoicePreferencesTests {
    @Test func managementRowsDistinguishProfilesAndStaleCustomPaths() {
        let system = BrowserDescriptor(id: "browser", bundleIdentifier: "browser", displayName: "Browser", applicationURL: URL(fileURLWithPath: "/Applications/Browser.app"), securityScopedBookmark: nil, origin: .system, availability: .available, selectorOrder: 0)
        let stale = BrowserDescriptor(id: system.id, bundleIdentifier: system.bundleIdentifier, displayName: system.displayName, applicationURL: URL(fileURLWithPath: "/Old/Browser.app"), securityScopedBookmark: nil, origin: .custom, availability: .unavailable, selectorOrder: 0)
        let profile = ChromiumProfileDescriptor(directoryName: "Profile 1", displayName: "Work", userDataDirectory: URL(fileURLWithPath: "/tmp/test"))
        let profileRow = BrowserDescriptor(id: profile.browserID(bundleIdentifier: system.bundleIdentifier), bundleIdentifier: system.bundleIdentifier, displayName: "Browser · Work", applicationURL: system.applicationURL, securityScopedBookmark: nil, origin: .system, availability: .available, selectorOrder: 1, profile: profile)
        #expect(Set([system, stale, profileRow].map(\.managementRowIdentity)).count == 3)
    }
    @Test func legacyOrderPayloadDefaultsToVisibleAndVisibilityPreservesOrder() throws {
        let record = try BrowserOrderRecord(ids: ["a", "b"])
        record.orderedIDsPayload = Data(#"{"version":1,"ids":["a","b"]}"#.utf8)
        #expect(try record.hiddenBrowserIDs().isEmpty)
        try record.replaceHiddenBrowserIDs(with: ["b"])
        #expect(try record.browserIDs() == ["a", "b"])
        try record.replace(with: ["b", "a"])
        #expect(try record.hiddenBrowserIDs() == ["b"])
    }

    @Test func preferencesSurviveSeparateRepositoryReadsAndIndependentUpdates() throws {
        let container = try ModelContainerFactory.make(inMemory: true).container
        let repository = SwiftDataBrowserPreferenceRepository(container: container)
        try repository.saveOrder(["a", "b"])
        try repository.saveHiddenBrowserIDs(["b"])
        let second = SwiftDataBrowserPreferenceRepository(container: container)
        #expect(try second.orderedBrowserIDs() == ["a", "b"])
        #expect(try second.hiddenBrowserIDs() == ["b"])
        try second.saveOrder(["b", "a"])
        let third = SwiftDataBrowserPreferenceRepository(container: container)
        #expect(try third.hiddenBrowserIDs() == ["b"])
        try third.saveHiddenBrowserIDs([])
        #expect(try third.orderedBrowserIDs() == ["b", "a"])
    }

    @Test func hiddenProfileIsAbsentFromChooserButAvailableToRulesAndFallback() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Chrome.app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.google.Chrome", "CFBundleName": "Chrome"], format: .xml, options: 0)
        try plist.write(to: contents.appending(path: "Info.plist"))
        let dataRoot = root.appending(path: "User Data")
        let directory = dataRoot.appending(path: "Profile 1")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"profile":{"info_cache":{"Profile 1":{"name":"工作"}}}}"#.utf8).write(to: dataRoot.appending(path: "Local State"))
        let preferences = InMemoryBrowserPreferenceRepository()
        let catalog = BrowserCatalogService(workspace: ChoiceWorkspace(applicationURL: app), browserPreferences: preferences, profileDiscovery: ChromiumProfileDiscovery(userDataDirectories: ["com.google.Chrome": dataRoot]))
        let all = try await catalog.scan()
        let profile = try #require(all.first { $0.profile != nil })
        try preferences.saveOrder([profile.id, "com.google.Chrome"])
        try preferences.saveHiddenBrowserIDs([profile.id])
        #expect(try await catalog.scanForSelector().map(\.id) == ["com.google.Chrome"])
        let available = Set(try await catalog.scan().map(\.id))
        let request = LinkRequest(id: UUID(), url: URL(string: "https://example.com")!, receivedAt: Date(), source: .unknown)
        let rule = RoutingRule(id: UUID(), isEnabled: true, matcher: .exactHost("example.com"), targetBrowserID: profile.id, priority: 0, label: nil, createdAt: Date(), updatedAt: Date())
        #expect(RuleEngine().decide(request: request, rules: [rule], availableBrowserIDs: available, eligibleSourceBundleIDs: [], settings: .defaults) == .open(browserID: profile.id, method: .urlRule, ruleID: rule.id))
        var settings = AppSettings.defaults
        settings.unmatchedBehavior = .preferredBrowser
        settings.preferredBrowserID = profile.id
        #expect(RuleEngine().decide(request: request, rules: [], availableBrowserIDs: available, eligibleSourceBundleIDs: [], settings: settings) == .open(browserID: profile.id, method: .preferredBrowser, ruleID: nil))
        try FileManager.default.removeItem(at: directory)
        let afterRemoval = Set(try await catalog.scan().map(\.id))
        #expect(RuleEngine().decide(request: request, rules: [rule], availableBrowserIDs: afterRemoval, eligibleSourceBundleIDs: [], settings: settings) == .ask(reason: .targetUnavailable(profile.id)))
    }

    @Test func chooserManagementOpensInternalSettingsAndConsumesRequestOnce() {
        let environment = AppEnvironment(route: .rules, unmatchedBehavior: .alwaysAsk, updateChecker: DisabledUpdateChecker(), ruleRepository: InMemoryRuleRepository(), historyRepository: InMemoryHistoryRepository(), browserPreferenceRepository: InMemoryBrowserPreferenceRepository(), settingsRepository: InMemorySettingsRepository())
        let opening = MainWindowOpening(updateRoute: environment.updateRoute)
        let navigation = AppSelectorNavigationHandler(environment: environment, mainWindowOpening: opening)
        navigation.openBrowserManagement()
        #expect(environment.route == .settings)
        #expect(environment.consumeBrowserManagement())
        #expect(!environment.consumeBrowserManagement())
    }
}

@MainActor
private struct ChoiceWorkspace: WorkspaceClient {
    let applicationURL: URL
    func applicationURLs(toOpen _: URL) -> [URL] { [applicationURL] }
    func open(_: URL, with _: URL) async throws { Issue.record("Preview tests must never launch an application") }
    func openApplication(at _: URL, arguments _: [String]) async throws { Issue.record("Preference tests must never launch a profile") }
    func icon(for _: URL) -> NSImage { NSImage() }
}
