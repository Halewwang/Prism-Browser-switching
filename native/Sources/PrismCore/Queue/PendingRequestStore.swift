import Foundation

public protocol PendingRequestStore: Sendable {
    func load() async throws -> PendingRequestSnapshot
    func save(_ snapshot: PendingRequestSnapshot) async throws
}
