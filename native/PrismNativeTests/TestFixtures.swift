import Foundation
import PrismCore

extension LinkRequest {
    static func fixture(
        id: UUID = UUID(),
        url: URL = URL(string: "https://example.com")!,
        receivedAt: Date = .now,
        source: SourceApplication = .unknown,
        state: LinkRequestState = .queued
    ) -> LinkRequest {
        LinkRequest(
            id: id,
            url: url,
            receivedAt: receivedAt,
            source: source,
            state: state
        )
    }
}

actor InMemoryPendingRequestStore: PendingRequestStore {
    private var snapshot: PendingRequestSnapshot

    init(snapshot: PendingRequestSnapshot = .init(pendingRequests: [], terminalRecords: [])) {
        self.snapshot = snapshot
    }

    func load() async throws -> PendingRequestSnapshot {
        snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        self.snapshot = snapshot
    }
}
