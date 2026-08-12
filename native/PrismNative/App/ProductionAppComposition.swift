import PrismCore

@MainActor
final class ProductionAppComposition {
    let environment: AppEnvironment
    private let recoveryQueue: LinkRequestQueue?
    private let warningSource: (any PersistenceWarningSource)?
    private var didRestore = false

    init(
        environment: AppEnvironment,
        recoveryQueue: LinkRequestQueue?,
        warningSource: (any PersistenceWarningSource)?
    ) {
        self.environment = environment
        self.recoveryQueue = recoveryQueue
        self.warningSource = warningSource
    }

    static func make() -> ProductionAppComposition {
        make(
            modelContainerFactory: { try ModelContainerFactory.make(inMemory: false) },
            recoveryStoreFactory: { try AtomicPendingRequestStore.makeDefault() }
        )
    }

    static func makeForTesting(
        modelContainerFactory: @escaping @MainActor () throws -> ModelContainerResult,
        recoveryStoreFactory: @escaping @MainActor () throws -> AtomicPendingRequestStore
    ) -> ProductionAppComposition {
        make(
            modelContainerFactory: modelContainerFactory,
            recoveryStoreFactory: recoveryStoreFactory
        )
    }

    func restoreOnce() async {
        guard !didRestore else { return }
        didRestore = true

        guard let recoveryQueue else { return }
        await environment.restoreAndReconcile(queue: recoveryQueue, warningSource: warningSource)
    }

    private static func make(
        modelContainerFactory: @escaping @MainActor () throws -> ModelContainerResult,
        recoveryStoreFactory: @escaping @MainActor () throws -> AtomicPendingRequestStore
    ) -> ProductionAppComposition {
        let containerResult: ModelContainerResult
        do {
            containerResult = try modelContainerFactory()
        } catch {
            return safeComposition(warnings: [.recoveryStoreUnavailable])
        }

        var warnings = containerResult.warning.map { [$0] } ?? []
        let recoveryStore: AtomicPendingRequestStore
        do {
            recoveryStore = try recoveryStoreFactory()
        } catch {
            warnings.append(.recoveryStoreUnavailable)
            return safeComposition(warnings: warnings)
        }

        let environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: SwiftDataRuleRepository(container: containerResult.container),
            historyRepository: SwiftDataHistoryRepository(container: containerResult.container),
            browserPreferenceRepository: SwiftDataBrowserPreferenceRepository(container: containerResult.container),
            settingsRepository: SwiftDataSettingsRepository(container: containerResult.container),
            persistenceWarnings: warnings
        )
        return ProductionAppComposition(
            environment: environment,
            recoveryQueue: LinkRequestQueue(store: recoveryStore),
            warningSource: recoveryStore
        )
    }

    private static func safeComposition(warnings: [PersistenceWarning]) -> ProductionAppComposition {
        let environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: InMemoryRuleRepository(),
            historyRepository: InMemoryHistoryRepository(),
            browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
            settingsRepository: InMemorySettingsRepository(),
            persistenceWarnings: warnings
        )
        return ProductionAppComposition(environment: environment, recoveryQueue: nil, warningSource: nil)
    }
}
