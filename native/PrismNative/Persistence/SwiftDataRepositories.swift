import Foundation
import PrismCore
import SwiftData

@MainActor
protocol RuleRepository {
    func all() throws -> [RoutingRule]
    func upsert(_ rule: RoutingRule) throws
    func delete(id: UUID) throws
}

@MainActor
protocol HistoryRepository {
    func upsert(_ entry: HistoryEntry) throws
    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry]
    func delete(id: UUID) throws
    func clear() throws
    func enforceRetention(limit: Int, cutoff: Date) throws
}

@MainActor
protocol BrowserPreferenceRepository {
    func orderedBrowserIDs() throws -> [BrowserID]
    func saveOrder(_ ids: [BrowserID]) throws
    func customBrowsers() throws -> [BrowserDescriptor]
    func upsertCustomBrowser(_ browser: BrowserDescriptor) throws
    func deleteCustomBrowser(id: BrowserID) throws
}

@MainActor
protocol SettingsRepository {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

@MainActor
final class SwiftDataRuleRepository: RuleRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func all() throws -> [RoutingRule] {
        try context.fetch(FetchDescriptor<RuleRecord>())
            .map { try $0.routingRule() }
            .sorted(by: RoutingRuleOrdering.isOrderedBefore)
    }

    func upsert(_ rule: RoutingRule) throws {
        if let record = try context.fetch(FetchDescriptor<RuleRecord>()).first(where: { $0.id == rule.id }) {
            try record.replace(with: rule)
        } else {
            context.insert(try RuleRecord(rule: rule))
        }
        try context.save()
    }

    func delete(id: UUID) throws {
        if let record = try context.fetch(FetchDescriptor<RuleRecord>()).first(where: { $0.id == id }) {
            context.delete(record)
            try context.save()
        }
    }

}

@MainActor
final class SwiftDataHistoryRepository: HistoryRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func upsert(_ entry: HistoryEntry) throws {
        if let record = try context.fetch(FetchDescriptor<HistoryRecord>()).first(where: { $0.id == entry.id }) {
            record.replace(with: entry)
        } else {
            context.insert(HistoryRecord(entry: entry))
        }
        try context.save()
    }

    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry] {
        guard limit > 0 else { return [] }
        return try context.fetch(FetchDescriptor<HistoryRecord>())
            .filter { $0.createdAt >= newerThan }
            .map { try $0.historyEntry() }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            .prefix(limit)
            .map { $0 }
    }

    func delete(id: UUID) throws {
        if let record = try context.fetch(FetchDescriptor<HistoryRecord>()).first(where: { $0.id == id }) {
            context.delete(record)
            try context.save()
        }
    }

    func clear() throws {
        for record in try context.fetch(FetchDescriptor<HistoryRecord>()) {
            context.delete(record)
        }
        try context.save()
    }

    func enforceRetention(limit: Int, cutoff: Date) throws {
        let records = try context.fetch(FetchDescriptor<HistoryRecord>())
        var remaining = records.filter { record in
            if record.createdAt < cutoff {
                context.delete(record)
                return false
            }
            return true
        }
        remaining.sort { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
        let retainedCount = max(limit, 0)
        for record in remaining.dropFirst(retainedCount) {
            context.delete(record)
        }
        try context.save()
    }
}

@MainActor
final class SwiftDataBrowserPreferenceRepository: BrowserPreferenceRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func orderedBrowserIDs() throws -> [BrowserID] {
        guard let record = try context.fetch(FetchDescriptor<BrowserOrderRecord>()).first(where: { $0.key == "primary" }) else {
            return []
        }
        return try record.browserIDs()
    }

    func saveOrder(_ ids: [BrowserID]) throws {
        if let record = try context.fetch(FetchDescriptor<BrowserOrderRecord>()).first(where: { $0.key == "primary" }) {
            try record.replace(with: ids)
        } else {
            context.insert(try BrowserOrderRecord(ids: ids))
        }
        try context.save()
    }

    func customBrowsers() throws -> [BrowserDescriptor] {
        try context.fetch(FetchDescriptor<CustomBrowserRecord>())
            .map { try $0.browserDescriptor() }
            .sorted {
                if $0.selectorOrder != $1.selectorOrder {
                    return $0.selectorOrder < $1.selectorOrder
                }
                return $0.id.rawValue < $1.id.rawValue
            }
    }

    func upsertCustomBrowser(_ browser: BrowserDescriptor) throws {
        if let record = try context.fetch(FetchDescriptor<CustomBrowserRecord>()).first(where: { $0.id == browser.id.rawValue }) {
            record.replace(with: browser)
        } else {
            context.insert(CustomBrowserRecord(browser: browser))
        }
        try context.save()
    }

    func deleteCustomBrowser(id: BrowserID) throws {
        if let record = try context.fetch(FetchDescriptor<CustomBrowserRecord>()).first(where: { $0.id == id.rawValue }) {
            context.delete(record)
            try context.save()
        }
    }
}

@MainActor
final class SwiftDataSettingsRepository: SettingsRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func load() throws -> AppSettings {
        guard let record = try context.fetch(FetchDescriptor<SettingsRecord>()).first(where: { $0.key == "current" }) else {
            return .defaults
        }
        return try record.appSettings()
    }

    func save(_ settings: AppSettings) throws {
        if let record = try context.fetch(FetchDescriptor<SettingsRecord>()).first(where: { $0.key == "current" }) {
            record.replace(with: settings)
        } else {
            context.insert(SettingsRecord(settings: settings))
        }
        try context.save()
    }
}

@MainActor
final class InMemoryRuleRepository: RuleRepository {
    private var rules: [UUID: RoutingRule] = [:]

    func all() throws -> [RoutingRule] {
        RoutingRuleOrdering.sorted(Array(rules.values))
    }

    func upsert(_ rule: RoutingRule) throws {
        rules[rule.id] = rule
    }

    func delete(id: UUID) throws {
        rules.removeValue(forKey: id)
    }
}

@MainActor
final class InMemoryHistoryRepository: HistoryRepository {
    private var entries: [UUID: HistoryEntry] = [:]

    func upsert(_ entry: HistoryEntry) throws {
        entries[entry.id] = entry
    }

    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry] {
        guard limit > 0 else { return [] }
        return entries.values
            .filter { $0.createdAt >= newerThan }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func delete(id: UUID) throws {
        entries.removeValue(forKey: id)
    }

    func clear() throws {
        entries.removeAll()
    }

    func enforceRetention(limit: Int, cutoff: Date) throws {
        entries = entries.filter { $0.value.createdAt >= cutoff }
        let retained = try recent(limit: max(limit, 0), newerThan: .distantPast)
        entries = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
    }
}

@MainActor
final class InMemoryBrowserPreferenceRepository: BrowserPreferenceRepository {
    private var orderedIDs: [BrowserID] = []
    private var browsers: [BrowserID: BrowserDescriptor] = [:]

    func orderedBrowserIDs() throws -> [BrowserID] {
        orderedIDs
    }

    func saveOrder(_ ids: [BrowserID]) throws {
        orderedIDs = ids
    }

    func customBrowsers() throws -> [BrowserDescriptor] {
        browsers.values.sorted { $0.selectorOrder < $1.selectorOrder }
    }

    func upsertCustomBrowser(_ browser: BrowserDescriptor) throws {
        browsers[browser.id] = browser
    }

    func deleteCustomBrowser(id: BrowserID) throws {
        browsers.removeValue(forKey: id)
    }
}

@MainActor
final class InMemorySettingsRepository: SettingsRepository {
    private var settings: AppSettings

    init(settings: AppSettings = .defaults) {
        self.settings = settings
    }

    func load() throws -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) throws {
        self.settings = settings
    }
}
