import Foundation
import PrismCore
import SwiftData

struct ModelContainerResult {
    let container: ModelContainer
    let warning: PersistenceWarning?
}

@MainActor
enum ModelContainerFactory {
    static func make(inMemory: Bool) throws -> ModelContainerResult {
        try make(inMemory: inMemory, storeURL: nil, simulatedOpenFailures: 0)
    }

    static func makeForTesting(
        inMemory: Bool,
        storeURL: URL
    ) throws -> ModelContainerResult {
        try make(
            inMemory: inMemory,
            storeURL: storeURL,
            simulatedOpenFailures: 0
        )
    }

    static func makeForTesting(
        inMemory: Bool,
        storeURL: URL,
        simulatedOpenFailures: Int
    ) throws -> ModelContainerResult {
        try make(
            inMemory: inMemory,
            storeURL: storeURL,
            simulatedOpenFailures: simulatedOpenFailures
        )
    }

    private static func make(
        inMemory: Bool,
        storeURL: URL?,
        simulatedOpenFailures: Int
    ) throws -> ModelContainerResult {
        let resolvedStoreURL = inMemory ? nil : try storeURL ?? persistentStoreURL()
        var remainingSimulatedOpenFailures = simulatedOpenFailures
        let openContainer = {
            if remainingSimulatedOpenFailures > 0 {
                remainingSimulatedOpenFailures -= 1
                throw ModelContainerFactoryError.simulatedOpenFailure
            }
            return try newContainer(inMemory: inMemory, storeURL: resolvedStoreURL)
        }

        do {
            return ModelContainerResult(
                container: try openContainer(),
                warning: nil
            )
        } catch {
            guard !inMemory, let resolvedStoreURL else {
                throw error
            }

            let backupDirectory = try backupStoreArtifacts(at: resolvedStoreURL)
            let container = try openContainer()
            try seedSafeSettings(in: container)
            return ModelContainerResult(
                container: container,
                warning: .corruptStoreRecovered(backupLocation: backupDirectory.path)
            )
        }
    }

    private static func newContainer(inMemory: Bool, storeURL: URL?) throws -> ModelContainer {
        let schema = Schema([
            RuleRecord.self,
            HistoryRecord.self,
            CustomBrowserRecord.self,
            BrowserOrderRecord.self,
            SettingsRecord.self
        ])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let storeURL {
            configuration = ModelConfiguration("PrismNative", schema: schema, url: storeURL)
        } else {
            throw ModelContainerFactoryError.missingStoreURL
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private static func seedSafeSettings(in container: ModelContainer) throws {
        var settings = AppSettings.defaults
        settings.automaticRulesEnabled = false
        settings.unmatchedBehavior = .alwaysAsk
        settings.schemaVersion = 1
        let context = ModelContext(container)
        context.insert(SettingsRecord(settings: settings))
        try context.save()
    }

    private static func persistentStoreURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let prismDirectory = directory.appending(path: "Prism")
        try FileManager.default.createDirectory(at: prismDirectory, withIntermediateDirectories: true)
        return prismDirectory.appending(path: "PrismNative.store")
    }

    private static func backupStoreArtifacts(at storeURL: URL) throws -> URL {
        let backupDirectory = storeURL.deletingLastPathComponent()
            .appending(path: "CorruptDataBackup")
            .appending(path: timestamp())
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let artifacts = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        for artifact in artifacts where fileManager.fileExists(atPath: artifact.path) {
            try fileManager.moveItem(at: artifact, to: backupDirectory.appending(path: artifact.lastPathComponent))
        }
        return backupDirectory
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private enum ModelContainerFactoryError: Error {
    case missingStoreURL
    case simulatedOpenFailure
}
