import Foundation
import PrismCore
import SwiftData

@MainActor
protocol RuleRepository {
    func all() throws -> [RoutingRule]
    func upsert(_ rule: RoutingRule) throws
    func updatePriorities(_ rules: [RoutingRule]) throws
    func delete(id: UUID) throws
}

extension RuleRepository {
    /// Test-only and simple in-memory conformers can use the existing upsert path.
    /// The production repository overrides this with one transactional save.
    func updatePriorities(_ rules: [RoutingRule]) throws {
        for rule in rules {
            try upsert(rule)
        }
    }
}

enum RuleRepositoryError: Error, Equatable {
    case missingRule(UUID)
}

@MainActor
protocol HistoryRepository {
    func upsert(_ entry: HistoryEntry) throws
    func upsertAndEnforceRetention(_ entry: HistoryEntry, limit: Int, cutoff: Date) throws
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

    func updatePriorities(_ rules: [RoutingRule]) throws {
        do {
            let records = try context.fetch(FetchDescriptor<RuleRecord>())
            for rule in rules {
                guard let record = records.first(where: { $0.id == rule.id }) else {
                    throw RuleRepositoryError.missingRule(rule.id)
                }
                try record.replace(with: rule)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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
        do {
            try upsertInContext(entry)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func upsertAndEnforceRetention(_ entry: HistoryEntry, limit: Int, cutoff: Date) throws {
        do {
            try upsertInContext(entry)
            try enforceRetentionInContext(limit: limit, cutoff: cutoff)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry] {
        guard limit > 0 else { return [] }
        let records = try context.fetch(FetchDescriptor<HistoryRecord>())
        var migratedLegacyURL = false
        do {
            let entries = try records.map { record -> HistoryEntry in
                let entry = try record.historyEntry()
                let safeURLString = entry.sanitizedURL?.absoluteString
                if record.sanitizedURLString != safeURLString {
                    record.sanitizedURLString = safeURLString
                    migratedLegacyURL = true
                }
                return entry
            }
            if migratedLegacyURL {
                try context.save()
            }
            return entries
                .filter { $0.createdAt >= newerThan }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                .prefix(limit)
                .map { $0 }
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(id: UUID) throws {
        do {
            if let record = try context.fetch(FetchDescriptor<HistoryRecord>()).first(where: { $0.id == id }) {
                context.delete(record)
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func clear() throws {
        do {
            for record in try context.fetch(FetchDescriptor<HistoryRecord>()) {
                context.delete(record)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func enforceRetention(limit: Int, cutoff: Date) throws {
        do {
            try enforceRetentionInContext(limit: limit, cutoff: cutoff)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func newestRecordFirst(_ lhs: HistoryRecord, _ rhs: HistoryRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func stableCanonicalRecordFirst(_ lhs: HistoryRecord, _ rhs: HistoryRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func upsertInContext(_ entry: HistoryEntry) throws {
        let records = try context.fetch(FetchDescriptor<HistoryRecord>())
        let requestRecords = records
            .filter { $0.requestID == entry.requestID }
            .sorted(by: Self.stableCanonicalRecordFirst)
        if let record = requestRecords.first
            ?? records.first(where: { $0.id == entry.id }) {
            record.replace(with: entry)
            for duplicate in requestRecords where duplicate !== record {
                context.delete(duplicate)
            }
        } else {
            context.insert(HistoryRecord(entry: entry))
        }
    }

    private func enforceRetentionInContext(limit: Int, cutoff: Date) throws {
        let records = try context.fetch(FetchDescriptor<HistoryRecord>())
        let retainedByAge = records.filter { record in
            if record.createdAt < cutoff {
                context.delete(record)
                return false
            }
            return true
        }

        var canonicalByRequestID: [UUID: HistoryRecord] = [:]
        for record in retainedByAge.sorted(by: Self.stableCanonicalRecordFirst) {
            if canonicalByRequestID[record.requestID] == nil {
                canonicalByRequestID[record.requestID] = record
            }
        }

        for (requestID, canonical) in canonicalByRequestID {
            let duplicates = retainedByAge.filter {
                $0.requestID == requestID && $0 !== canonical
            }
            if let latest = ([canonical] + duplicates).sorted(by: Self.latestPayloadRecordFirst).first,
               latest !== canonical {
                canonical.replace(with: try latest.historyEntry())
            }
            for duplicate in duplicates {
                context.delete(duplicate)
            }
        }

        let remaining = Array(canonicalByRequestID.values).sorted(by: Self.newestRecordFirst)
        for record in remaining.dropFirst(max(limit, 0)) {
            context.delete(record)
        }
    }

    private static func latestPayloadRecordFirst(_ lhs: HistoryRecord, _ rhs: HistoryRecord) -> Bool {
        if lhs.attemptCount != rhs.attemptCount { return lhs.attemptCount > rhs.attemptCount }
        let lhsCompletedAt = lhs.completedAt ?? .distantPast
        let rhsCompletedAt = rhs.completedAt ?? .distantPast
        if lhsCompletedAt != rhsCompletedAt { return lhsCompletedAt > rhsCompletedAt }
        let resultRank: [String: Int] = [
            HistoryResult.success.rawValue: 3,
            HistoryResult.failure.rawValue: 2,
            HistoryResult.cancelled.rawValue: 1,
            HistoryResult.processing.rawValue: 0,
        ]
        if resultRank[lhs.result, default: -1] != resultRank[rhs.result, default: -1] {
            return resultRank[lhs.result, default: -1] > resultRank[rhs.result, default: -1]
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString > rhs.id.uuidString
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

    func updatePriorities(_ updatedRules: [RoutingRule]) throws {
        var nextRules = rules
        for rule in updatedRules {
            guard nextRules[rule.id] != nil else {
                throw RuleRepositoryError.missingRule(rule.id)
            }
            nextRules[rule.id] = rule
        }
        rules = nextRules
    }

    func delete(id: UUID) throws {
        rules.removeValue(forKey: id)
    }
}

@MainActor
final class InMemoryHistoryRepository: HistoryRepository {
    private var entriesByRequestID: [UUID: HistoryEntry] = [:]

    func upsert(_ entry: HistoryEntry) throws {
        if let existing = entriesByRequestID[entry.requestID] {
            entriesByRequestID[entry.requestID] = entry.preservingHistoryID(existing.id)
        } else {
            entriesByRequestID[entry.requestID] = entry
        }
    }

    func upsertAndEnforceRetention(_ entry: HistoryEntry, limit: Int, cutoff: Date) throws {
        let previous = entriesByRequestID
        do {
            try upsert(entry)
            try enforceRetention(limit: limit, cutoff: cutoff)
        } catch {
            entriesByRequestID = previous
            throw error
        }
    }

    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry] {
        guard limit > 0 else { return [] }
        return entriesByRequestID.values
            .filter { $0.createdAt >= newerThan }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func delete(id: UUID) throws {
        guard let requestID = entriesByRequestID.first(where: { $0.value.id == id })?.key else { return }
        entriesByRequestID.removeValue(forKey: requestID)
    }

    func clear() throws {
        entriesByRequestID.removeAll()
    }

    func enforceRetention(limit: Int, cutoff: Date) throws {
        entriesByRequestID = entriesByRequestID.filter { $0.value.createdAt >= cutoff }
        let retained = try recent(limit: max(limit, 0), newerThan: .distantPast)
        entriesByRequestID = Dictionary(uniqueKeysWithValues: retained.map { ($0.requestID, $0) })
    }
}

private extension HistoryEntry {
    func preservingHistoryID(_ id: UUID) -> HistoryEntry {
        HistoryEntry(
            id: id,
            requestID: requestID,
            sanitizedURL: sanitizedURL,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceDisplayName: sourceDisplayName,
            targetBrowserID: targetBrowserID,
            targetDisplayName: targetDisplayName,
            method: method,
            result: result,
            matchingRuleID: matchingRuleID,
            failureReason: failureReason,
            attemptCount: attemptCount,
            createdAt: createdAt,
            completedAt: completedAt
        )
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
