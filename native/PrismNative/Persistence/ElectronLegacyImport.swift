import Foundation
import PrismCore

struct ElectronLegacyImportResult: Equatable {
    var importedRuleCount = 0
    var importedHistoryCount = 0
    var importedCustomBrowserCount = 0
    var skippedBecauseAlreadyImported = false
    var skippedBecauseNativeDataExists = false
}

enum ElectronLegacyImport {
    static let markerFileName = "ElectronLegacyImport.v1.completed"

    @MainActor
    static func runIfNeeded(
        rules: any RuleRepository,
        history: any HistoryRepository,
        browsers: any BrowserPreferenceRepository,
        fileManager: FileManager = .default,
        applicationSupportRoots: [URL]? = nil,
        now: Date = .now
    ) throws -> ElectronLegacyImportResult {
        let roots = try applicationSupportRoots ?? defaultApplicationSupportRoots(fileManager: fileManager)
        guard let prismDirectory = roots.first else {
            return ElectronLegacyImportResult()
        }
        let markerURL = prismDirectory.appending(path: markerFileName)
        if fileManager.fileExists(atPath: markerURL.path) {
            return ElectronLegacyImportResult(skippedBecauseAlreadyImported: true)
        }

        let existingRules = (try? rules.all()) ?? []
        let existingHistory = (try? history.recent(limit: 1, newerThan: .distantPast)) ?? []
        let existingBrowsers = (try? browsers.customBrowsers()) ?? []
        if !existingRules.isEmpty || !existingHistory.isEmpty || !existingBrowsers.isEmpty {
            try writeMarker(at: markerURL, fileManager: fileManager)
            return ElectronLegacyImportResult(skippedBecauseNativeDataExists: true)
        }

        let snapshot = loadSnapshot(from: roots, fileManager: fileManager)
        var result = ElectronLegacyImportResult()
        result.importedCustomBrowserCount = try importCustomBrowsers(
            snapshot.customBrowsers,
            into: browsers
        )
        result.importedRuleCount = try importRules(
            snapshot.rules,
            customBrowsers: snapshot.customBrowsers,
            into: rules,
            now: now
        )
        result.importedHistoryCount = try importHistory(
            snapshot.history,
            customBrowsers: snapshot.customBrowsers,
            into: history
        )
        try writeMarker(at: markerURL, fileManager: fileManager)
        return result
    }

    static func loadSnapshot(
        from roots: [URL],
        fileManager: FileManager = .default
    ) -> ElectronLegacySnapshot {
        var snapshot = ElectronLegacySnapshot()
        for root in roots {
            if snapshot.customBrowsers.isEmpty {
                snapshot.customBrowsers = decodeArray(
                    ElectronCustomBrowserPayload.self,
                    at: root.appending(path: "custom-browsers.json"),
                    fileManager: fileManager
                )
            }

            let rulesURL = root.appending(path: "routingRules.json")
            if snapshot.rules.isEmpty {
                snapshot.rules = decodeArray(
                    ElectronRoutingRulePayload.self,
                    at: rulesURL,
                    fileManager: fileManager
                )
            }
            let historyURL = root.appending(path: "routingHistory.json")
            if snapshot.history.isEmpty {
                snapshot.history = decodeArray(
                    ElectronHistoryPayload.self,
                    at: historyURL,
                    fileManager: fileManager
                )
            }

            let localStorage = root.appending(path: "Local Storage").appending(path: "leveldb")
            let stored = ChromiumLocalStorageReader.stringValues(
                in: localStorage,
                keys: ["routingRules", "routingHistory"],
                fileManager: fileManager
            )
            if snapshot.rules.isEmpty, let json = stored["routingRules"] {
                snapshot.rules = decodeArray(ElectronRoutingRulePayload.self, fromJSON: json)
            }
            if snapshot.history.isEmpty, let json = stored["routingHistory"] {
                snapshot.history = decodeArray(ElectronHistoryPayload.self, fromJSON: json)
            }
        }
        return snapshot
    }

    private static func importCustomBrowsers(
        _ payloads: [ElectronCustomBrowserPayload],
        into browsers: any BrowserPreferenceRepository
    ) throws -> Int {
        var imported = 0
        for (index, payload) in payloads.enumerated() {
            guard let browser = ElectronLegacyMapping.customBrowser(from: payload, selectorOrder: index) else {
                continue
            }
            try browsers.upsertCustomBrowser(browser)
            imported += 1
        }
        return imported
    }

    private static func importRules(
        _ payloads: [ElectronRoutingRulePayload],
        customBrowsers: [ElectronCustomBrowserPayload],
        into rules: any RuleRepository,
        now: Date
    ) throws -> Int {
        var imported = 0
        for (index, payload) in payloads.enumerated() {
            guard var rule = ElectronLegacyMapping.routingRule(
                from: payload,
                customBrowsers: customBrowsers,
                now: now
            ) else {
                continue
            }
            rule.priority = index
            try rules.upsert(rule)
            imported += 1
        }
        return imported
    }

    private static func importHistory(
        _ payloads: [ElectronHistoryPayload],
        customBrowsers: [ElectronCustomBrowserPayload],
        into history: any HistoryRepository
    ) throws -> Int {
        let entries = payloads.compactMap {
            ElectronLegacyMapping.historyEntry(from: $0, customBrowsers: customBrowsers)
        }
        .sorted { $0.createdAt > $1.createdAt }
        let limit = AppSettings.defaults.historyLimit
        var imported = 0
        for entry in entries.prefix(max(limit, 0)) {
            try history.upsert(entry)
            imported += 1
        }
        return imported
    }

    private static func defaultApplicationSupportRoots(fileManager: FileManager) throws -> [URL] {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let prism = support.appending(path: "Prism")
        try fileManager.createDirectory(at: prism, withIntermediateDirectories: true)
        return [
            prism,
            support.appending(path: "prism-app")
        ]
    }

    private static func writeMarker(at url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("imported\n".utf8).write(to: url, options: .atomic)
    }

    private static func decodeArray<T: Decodable>(
        _ type: T.Type,
        at url: URL,
        fileManager: FileManager
    ) -> [T] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return []
        }
        return decodeArray(type, from: data)
    }

    private static func decodeArray<T: Decodable>(_ type: T.Type, fromJSON json: String) -> [T] {
        decodeArray(type, from: Data(json.utf8))
    }

    private static func decodeArray<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([T].self, from: data)) ?? []
    }
}

struct ElectronLegacySnapshot: Equatable {
    var rules: [ElectronRoutingRulePayload] = []
    var history: [ElectronHistoryPayload] = []
    var customBrowsers: [ElectronCustomBrowserPayload] = []
}
