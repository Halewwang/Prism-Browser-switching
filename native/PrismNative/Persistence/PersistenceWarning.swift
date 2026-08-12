import Foundation

enum PersistenceWarning: Equatable, Sendable {
    case historyNotSaved
    case recoveryStoreUnavailable
    case settingsNotSaved
    case corruptStoreRecovered(backupLocation: String)
}

protocol PersistenceWarningSource: Sendable {
    func drainPersistenceWarnings() async -> [PersistenceWarning]
}
