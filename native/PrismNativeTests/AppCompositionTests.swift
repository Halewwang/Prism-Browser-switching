import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func productionCompositionFallsBackToSafeEnvironmentWhenPersistenceCannotStart() {
    let modelFailure = ProductionAppComposition.makeForTesting(
        modelContainerFactory: { throw TestCompositionFailure.unavailable },
        recoveryStoreFactory: { throw TestCompositionFailure.unavailable }
    )

    #expect(modelFailure.environment.unmatchedBehavior == .alwaysAsk)
    #expect(modelFailure.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))

    let recoveryFailure = ProductionAppComposition.makeForTesting(
        modelContainerFactory: { try ModelContainerFactory.make(inMemory: true) },
        recoveryStoreFactory: { throw TestCompositionFailure.unavailable }
    )

    #expect(recoveryFailure.environment.unmatchedBehavior == .alwaysAsk)
    #expect(recoveryFailure.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
}

@Test @MainActor func productionCompositionRestoresOnlyOnce() async {
    let store = CountingLoadStore()
    let composition = ProductionAppComposition(
        environment: AppEnvironment.preview,
        recoveryQueue: LinkRequestQueue(store: store),
        warningSource: nil
    )

    await composition.restoreOnce()
    await composition.restoreOnce()

    #expect(await store.loadCount == 1)
}

private enum TestCompositionFailure: Error {
    case unavailable
}

private actor CountingLoadStore: PendingRequestStore {
    private(set) var loadCount = 0

    func load() async throws -> PendingRequestSnapshot {
        loadCount += 1
        return PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])
    }

    func save(_: PendingRequestSnapshot) async throws {}
}
