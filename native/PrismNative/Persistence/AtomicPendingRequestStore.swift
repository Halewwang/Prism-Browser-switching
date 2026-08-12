import Foundation
import PrismCore

actor AtomicPendingRequestStore: PendingRequestStore, PersistenceWarningSource {
    private static let filename = "pending-requests-v1.json"
    private static let schemaVersion = 1

    private let directory: URL
    private var warnings: [PersistenceWarning] = []

    init(directory: URL) {
        self.directory = directory
    }

    static func makeDefault() throws -> AtomicPendingRequestStore {
        try AtomicPendingRequestStore(directory: defaultDirectory())
    }

    static func makeForTesting(
        resolvingDefaultDirectoryWith resolver: () throws -> URL
    ) throws -> AtomicPendingRequestStore {
        try AtomicPendingRequestStore(directory: resolver())
    }

    func load() async throws -> PendingRequestSnapshot {
        let fileURL = recoveryFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder().decode(RecoveryEnvelope.self, from: data)
            guard envelope.schemaVersion == Self.schemaVersion else {
                throw RecoveryStoreError.unsupportedSchema
            }
            return envelope.snapshot
        } catch {
            let backupLocation = try preserveCorruptRecoveryFile(at: fileURL)
            let empty = PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])
            try write(empty)
            warnings.append(.corruptStoreRecovered(backupLocation: backupLocation.path))
            return empty
        }
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        try write(snapshot)
    }

    func drainPersistenceWarnings() async -> [PersistenceWarning] {
        defer { warnings.removeAll() }
        return warnings
    }

    private var recoveryFileURL: URL {
        directory.appending(path: Self.filename)
    }

    private func write(_ snapshot: PendingRequestSnapshot) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = recoveryFileURL
        let temporary = directory.appending(path: ".\(Self.filename).\(UUID().uuidString).tmp")
        let data = try JSONEncoder().encode(RecoveryEnvelope(schemaVersion: Self.schemaVersion, snapshot: snapshot))
        guard fileManager.createFile(atPath: temporary.path, contents: data) else {
            throw RecoveryStoreError.temporaryFileCreationFailed
        }

        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()

            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func preserveCorruptRecoveryFile(at fileURL: URL) throws -> URL {
        let timestamp = Self.timestamp()
        let backupDirectory = directory
            .appending(path: "CorruptRecoveryBackup")
            .appending(path: timestamp)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: fileURL, to: backupDirectory.appending(path: Self.filename))
        return backupDirectory
    }

    private static func defaultDirectory() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appending(path: "Prism")
            .appending(path: "Recovery")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private struct RecoveryEnvelope: Codable {
    let schemaVersion: Int
    let snapshot: PendingRequestSnapshot
}

private enum RecoveryStoreError: Error {
    case unsupportedSchema
    case temporaryFileCreationFailed
}
