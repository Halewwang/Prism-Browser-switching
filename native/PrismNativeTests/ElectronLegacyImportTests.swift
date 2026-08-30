import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("Electron legacy mapping")
struct ElectronLegacyMappingTests {
    @Test func sourceRulesResolveBundleIDsAndKeepAHumanLabel() {
        let payload = ElectronRoutingRulePayload(
            id: "r1",
            type: "SOURCE_APP",
            value: "Slack",
            targetBrowserId: "b2",
            description: "Work",
            active: true,
            appName: "Slack"
        )

        let rule = ElectronLegacyMapping.routingRule(
            from: payload,
            customBrowsers: [],
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(rule?.matcher == .sourceBundleIdentifier("com.tinyspeck.slackmacgap"))
        #expect(rule?.targetBrowserID == BrowserID("com.google.Chrome"))
        #expect(rule?.label == "Slack")
        #expect(rule?.isEnabled == true)
    }

    @Test func urlRulesBecomeContainsMatchersAndMapElectronBrowserIDs() {
        let payload = ElectronRoutingRulePayload(
            id: "r2",
            type: "URL_PATTERN",
            value: "github.com",
            targetBrowserId: "b3",
            description: "Code",
            active: false,
            appName: nil
        )

        let rule = ElectronLegacyMapping.routingRule(
            from: payload,
            customBrowsers: [],
            now: Date(timeIntervalSince1970: 10)
        )

        #expect(rule?.matcher == .urlContains("github.com"))
        #expect(rule?.targetBrowserID == BrowserID("com.apple.Safari"))
        #expect(rule?.label == "Code")
        #expect(rule?.isEnabled == false)
    }

    @Test func historyNeverUsesABundleIDAsTheSourceTitle() {
        let payload = ElectronHistoryPayload(
            id: "h1",
            timestamp: nil,
            url: "https://example.com/private?token=secret",
            sourceApp: nil,
            sourceBundleId: "com.tinyspeck.slackmacgap",
            routedToBrowserId: "b2",
            method: "Manual"
        )

        let entry = ElectronLegacyMapping.historyEntry(from: payload, customBrowsers: [])

        #expect(entry?.sourceDisplayName == "Unknown")
        #expect(entry?.sourceBundleIdentifier == "com.tinyspeck.slackmacgap")
        #expect(entry?.targetBrowserID == BrowserID("com.google.Chrome"))
        #expect(entry?.method == .manual)
        #expect(entry?.sanitizedURL?.absoluteString == "https://example.com/private")
    }

    @Test func customBrowsersKeepTheirBundleIDAndPath() {
        let payload = ElectronCustomBrowserPayload(
            id: "custom-1",
            name: "Orion",
            bundleId: "com.kagi.kagimacOS",
            path: "/Applications/Orion.app",
            selectorOrder: 3
        )

        let browser = ElectronLegacyMapping.customBrowser(from: payload, selectorOrder: 0)

        #expect(browser?.id == BrowserID("com.kagi.kagimacOS"))
        #expect(browser?.bundleIdentifier == "com.kagi.kagimacOS")
        #expect(browser?.displayName == "Orion")
        #expect(browser?.applicationURL.path == "/Applications/Orion.app")
        #expect(browser?.origin == .custom)
    }

    @Test func nameOnlySourceRulesAreSkippedWhenTheyCannotBeResolved() {
        let payload = ElectronRoutingRulePayload(
            id: "r3",
            type: "SOURCE_APP",
            value: "An App That Never Existed",
            targetBrowserId: "b2",
            description: nil,
            active: true,
            appName: "An App That Never Existed"
        )

        #expect(ElectronLegacyMapping.routingRule(from: payload, customBrowsers: [], now: .now) == nil)
    }
}

@Suite("Chromium local storage reader")
struct ChromiumLocalStorageReaderTests {
    @Test func extractsUTF8AndUTF16JSONAfterTheKey() {
        let utf8 = Data("xxroutingRules[{\"id\":\"r1\"}]yy".utf8)
        #expect(ChromiumLocalStorageReader.extractJSON(afterKey: "routingRules", in: utf8) == "[{\"id\":\"r1\"}]")

        var utf16 = Data("prefix".utf8)
        utf16.append("routingHistory".data(using: .utf16LittleEndian)!)
        utf16.append("[{\"id\":\"h1\"}]".data(using: .utf16LittleEndian)!)
        #expect(ChromiumLocalStorageReader.extractJSON(afterKey: "routingHistory", in: utf16) == "[{\"id\":\"h1\"}]")
    }
}

@Suite("Electron legacy import")
struct ElectronLegacyImportTests {
    @Test @MainActor func importsRulesHistoryAndCustomBrowsersOnce() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rulesJSON = """
        [{"id":"r1","type":"SOURCE_APP","value":"com.tinyspeck.slackmacgap","targetBrowserId":"b2","active":true,"appName":"Slack"}]
        """
        let historyJSON = """
        [{"id":"h1","timestamp":"2026-01-02T03:04:05Z","url":"https://github.com","sourceApp":"Slack","sourceBundleId":"com.tinyspeck.slackmacgap","routedToBrowserId":"b3","method":"Rule"}]
        """
        let browsersJSON = """
        [{"id":"custom-1","name":"Orion","bundleId":"com.kagi.kagimacOS","path":"/Applications/Orion.app"}]
        """
        try Data(rulesJSON.utf8).write(to: root.appending(path: "routingRules.json"))
        try Data(historyJSON.utf8).write(to: root.appending(path: "routingHistory.json"))
        try Data(browsersJSON.utf8).write(to: root.appending(path: "custom-browsers.json"))

        let rules = InMemoryRuleRepository()
        let history = InMemoryHistoryRepository()
        let browsers = InMemoryBrowserPreferenceRepository()

        let first = try ElectronLegacyImport.runIfNeeded(
            rules: rules,
            history: history,
            browsers: browsers,
            applicationSupportRoots: [root],
            now: Date(timeIntervalSince1970: 50)
        )
        let second = try ElectronLegacyImport.runIfNeeded(
            rules: rules,
            history: history,
            browsers: browsers,
            applicationSupportRoots: [root]
        )

        #expect(first.importedRuleCount == 1)
        #expect(first.importedHistoryCount == 1)
        #expect(first.importedCustomBrowserCount == 1)
        #expect(second.skippedBecauseAlreadyImported)
        #expect(try rules.all().first?.matcher == .sourceBundleIdentifier("com.tinyspeck.slackmacgap"))
        #expect(try rules.all().first?.label == "Slack")
        #expect(try history.recent(limit: 10, newerThan: .distantPast).first?.sourceDisplayName == "Slack")
        #expect(try browsers.customBrowsers().first?.bundleIdentifier == "com.kagi.kagimacOS")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: ElectronLegacyImport.markerFileName).path))
    }

    @Test @MainActor func readsLocalStorageWhenJSONSidecarsAreMissing() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let leveldb = root.appending(path: "Local Storage").appending(path: "leveldb")
        try FileManager.default.createDirectory(at: leveldb, withIntermediateDirectories: true)
        let blob = Data("noise routingRules[{\"id\":\"r9\",\"type\":\"URL_PATTERN\",\"value\":\"docs.example\",\"targetBrowserId\":\"b3\",\"active\":true}] trailing".utf8)
        try blob.write(to: leveldb.appending(path: "000003.log"))

        let snapshot = ElectronLegacyImport.loadSnapshot(from: [root])

        #expect(snapshot.rules.count == 1)
        #expect(snapshot.rules.first?.value == "docs.example")
    }

    @Test @MainActor func skipsImportWhenNativeDataAlreadyExists() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: root.appending(path: "routingRules.json"))

        let rules = InMemoryRuleRepository()
        try rules.upsert(
            RoutingRule(
                id: UUID(),
                isEnabled: true,
                matcher: .urlContains("already-native"),
                targetBrowserID: "com.apple.Safari",
                priority: 0,
                label: "Native",
                createdAt: .now,
                updatedAt: .now
            )
        )

        let result = try ElectronLegacyImport.runIfNeeded(
            rules: rules,
            history: InMemoryHistoryRepository(),
            browsers: InMemoryBrowserPreferenceRepository(),
            applicationSupportRoots: [root]
        )

        #expect(result.skippedBecauseNativeDataExists)
        #expect(try rules.all().count == 1)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: ElectronLegacyImport.markerFileName).path))
    }
}
