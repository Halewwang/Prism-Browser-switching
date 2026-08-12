import Foundation
import PrismCore

@MainActor
final class ProductionAppComposition {
    let environment: AppEnvironment
    let recoveryQueue: LinkRequestQueue
    let bootstrapBuffer: BootstrapLinkBuffer
    let linkRoutingCoordinator: LinkRoutingCoordinator
    let linkIntakeService: LinkIntakeService
    let defaultBrowserService: DefaultBrowserService
    let loginItemService: LoginItemService
    let selectorPresentationRelay: SelectorPresentationRelay
    let activationTracker: ApplicationActivationTracker

    private let warningSource: (any PersistenceWarningSource)?
    private var didRestore = false
    private var restoreSucceeded = false
    private var didFinishLaunching = false
    private(set) var finishLaunchCount = 0

    init(
        environment: AppEnvironment,
        recoveryQueue: LinkRequestQueue,
        warningSource: (any PersistenceWarningSource)?,
        bootstrapBuffer: BootstrapLinkBuffer,
        linkRoutingCoordinator: LinkRoutingCoordinator,
        linkIntakeService: LinkIntakeService,
        defaultBrowserService: DefaultBrowserService,
        loginItemService: LoginItemService,
        selectorPresentationRelay: SelectorPresentationRelay? = nil,
        activationTracker: ApplicationActivationTracker? = nil
    ) {
        self.environment = environment
        self.recoveryQueue = recoveryQueue
        self.warningSource = warningSource
        self.bootstrapBuffer = bootstrapBuffer
        self.linkRoutingCoordinator = linkRoutingCoordinator
        self.linkIntakeService = linkIntakeService
        self.defaultBrowserService = defaultBrowserService
        self.loginItemService = loginItemService
        self.selectorPresentationRelay = selectorPresentationRelay ?? SelectorPresentationRelay()
        self.activationTracker = activationTracker ?? ApplicationActivationTracker()
    }

    convenience init(
        environment: AppEnvironment,
        recoveryQueue: LinkRequestQueue?,
        warningSource: (any PersistenceWarningSource)?
    ) {
        let queue = recoveryQueue ?? LinkRequestQueue(store: SessionPendingRequestStore())
        let bootstrap = BootstrapLinkBuffer()
        let relay = SelectorPresentationRelay()
        let tracker = ApplicationActivationTracker()
        let catalog = BrowserCatalogService(browserPreferences: environment.browserPreferenceRepository)
        let coordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: environment.ruleRepository,
            historyRepository: environment.historyRepository,
            settingsRepository: environment.settingsRepository,
            browserCatalog: catalog,
            browserLauncher: BrowserLauncherService(),
            sourceManifest: .disabled,
            presenter: relay,
            warningPresenter: environment
        )
        let intake = LinkIntakeService(
            queue: queue,
            bootstrap: bootstrap,
            sourceAttributor: SourceAttributionProvider(),
            lastActivatedSource: { [weak tracker] in tracker?.lastActivatedApplication },
            coordinator: coordinator,
            warningPresenter: environment
        )
        let defaultBrowser = DefaultBrowserService()
        let loginItem = LoginItemService()
        if environment.linkRoutingCoordinator == nil {
            environment.connectLinkRouting(
                coordinator: coordinator,
                intake: intake,
                defaultBrowserService: defaultBrowser,
                loginItemService: loginItem
            )
        }
        self.init(
            environment: environment,
            recoveryQueue: queue,
            warningSource: warningSource,
            bootstrapBuffer: bootstrap,
            linkRoutingCoordinator: coordinator,
            linkIntakeService: intake,
            defaultBrowserService: defaultBrowser,
            loginItemService: loginItem,
            selectorPresentationRelay: relay,
            activationTracker: tracker
        )
    }

    static func make(
        bootstrapBuffer: BootstrapLinkBuffer,
        diagnosticRecorder: (@MainActor (LinkCaptureDiagnostic) -> Void)? = nil
    ) -> ProductionAppComposition {
        make(
            bootstrapBuffer: bootstrapBuffer,
            diagnosticRecorder: diagnosticRecorder,
            modelContainerFactory: { try ModelContainerFactory.make(inMemory: false) },
            recoveryStoreFactory: { try AtomicPendingRequestStore.makeDefault() }
        )
    }

    static func make() -> ProductionAppComposition {
        make(bootstrapBuffer: BootstrapLinkBuffer())
    }

    static func makeForTesting(
        bootstrapBuffer: BootstrapLinkBuffer = BootstrapLinkBuffer(),
        modelContainerFactory: @escaping @MainActor () throws -> ModelContainerResult,
        recoveryStoreFactory: @escaping @MainActor () throws -> AtomicPendingRequestStore
    ) -> ProductionAppComposition {
        make(
            bootstrapBuffer: bootstrapBuffer,
            diagnosticRecorder: nil,
            modelContainerFactory: modelContainerFactory,
            recoveryStoreFactory: recoveryStoreFactory
        )
    }

    @discardableResult
    func restoreOnce() async -> Bool {
        guard !didRestore else { return restoreSucceeded }
        didRestore = true
        restoreSucceeded = await environment.restoreAndReconcile(
            queue: recoveryQueue,
            warningSource: warningSource
        )
        return restoreSucceeded
    }

    func finishLaunchingOnce() async {
        guard !didFinishLaunching else { return }
        didFinishLaunching = true
        finishLaunchCount += 1
        guard await restoreOnce() else { return }
        linkIntakeService.finishRestorationAndStartDraining()
    }

    private static func make(
        bootstrapBuffer: BootstrapLinkBuffer,
        diagnosticRecorder: (@MainActor (LinkCaptureDiagnostic) -> Void)?,
        modelContainerFactory: @escaping @MainActor () throws -> ModelContainerResult,
        recoveryStoreFactory: @escaping @MainActor () throws -> AtomicPendingRequestStore
    ) -> ProductionAppComposition {
        let repositories: RepositorySet
        var warnings: [PersistenceWarning] = []
        do {
            let containerResult = try modelContainerFactory()
            if let warning = containerResult.warning {
                warnings.append(warning)
            }
            repositories = RepositorySet(
                rules: SwiftDataRuleRepository(container: containerResult.container),
                history: SwiftDataHistoryRepository(container: containerResult.container),
                browsers: SwiftDataBrowserPreferenceRepository(container: containerResult.container),
                settings: SwiftDataSettingsRepository(container: containerResult.container)
            )
        } catch {
            warnings.append(.recoveryStoreUnavailable)
            repositories = .unavailable
        }

        let queue: LinkRequestQueue
        let warningSource: (any PersistenceWarningSource)?
        do {
            let store = try recoveryStoreFactory()
            queue = LinkRequestQueue(store: store)
            warningSource = store
        } catch {
            warnings.append(.recoveryStoreUnavailable)
            queue = LinkRequestQueue(store: UnavailablePendingRequestStore())
            warningSource = nil
        }

        let environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: repositories.rules,
            historyRepository: repositories.history,
            browserPreferenceRepository: repositories.browsers,
            settingsRepository: repositories.settings,
            persistenceWarnings: warnings
        )
        let workspace = SystemWorkspaceClient()
        let catalog = BrowserCatalogService(
            workspace: workspace,
            browserPreferences: repositories.browsers
        )
        let launcher = BrowserLauncherService(workspace: workspace)
        let relay = SelectorPresentationRelay()
        let tracker = ApplicationActivationTracker()
        let sourceAttributor = SourceAttributionProvider()
        let coordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: repositories.rules,
            historyRepository: repositories.history,
            settingsRepository: repositories.settings,
            browserCatalog: catalog,
            browserLauncher: launcher,
            sourceManifest: SourceSupportManifest.bundled(),
            presenter: relay,
            warningPresenter: environment
        )
        let intake = LinkIntakeService(
            queue: queue,
            bootstrap: bootstrapBuffer,
            sourceAttributor: sourceAttributor,
            lastActivatedSource: { [weak tracker] in tracker?.lastActivatedApplication },
            coordinator: coordinator,
            warningPresenter: environment,
            diagnosticRecorder: diagnosticRecorder
        )
        let defaultBrowser = DefaultBrowserService()
        let loginItem = LoginItemService()
        environment.connectLinkRouting(
            coordinator: coordinator,
            intake: intake,
            defaultBrowserService: defaultBrowser,
            loginItemService: loginItem
        )

        return ProductionAppComposition(
            environment: environment,
            recoveryQueue: queue,
            warningSource: warningSource,
            bootstrapBuffer: bootstrapBuffer,
            linkRoutingCoordinator: coordinator,
            linkIntakeService: intake,
            defaultBrowserService: defaultBrowser,
            loginItemService: loginItem,
            selectorPresentationRelay: relay,
            activationTracker: tracker
        )
    }
}

@MainActor
private struct RepositorySet {
    let rules: any RuleRepository
    let history: any HistoryRepository
    let browsers: any BrowserPreferenceRepository
    let settings: any SettingsRepository

    static var unavailable: RepositorySet {
        let repositories = UnavailableRepositories()
        return RepositorySet(
            rules: repositories,
            history: repositories,
            browsers: repositories,
            settings: repositories
        )
    }
}

@MainActor
private final class UnavailableRepositories:
    RuleRepository,
    HistoryRepository,
    BrowserPreferenceRepository,
    SettingsRepository
{
    private enum RepositoryError: Error {
        case unavailable
    }

    func all() throws -> [RoutingRule] { throw RepositoryError.unavailable }
    func upsert(_: RoutingRule) throws { throw RepositoryError.unavailable }
    func delete(id _: UUID) throws { throw RepositoryError.unavailable }

    func upsert(_: HistoryEntry) throws { throw RepositoryError.unavailable }
    func recent(limit _: Int, newerThan _: Date) throws -> [HistoryEntry] {
        throw RepositoryError.unavailable
    }
    func clear() throws { throw RepositoryError.unavailable }
    func enforceRetention(limit _: Int, cutoff _: Date) throws { throw RepositoryError.unavailable }

    func orderedBrowserIDs() throws -> [BrowserID] { throw RepositoryError.unavailable }
    func saveOrder(_: [BrowserID]) throws { throw RepositoryError.unavailable }
    func customBrowsers() throws -> [BrowserDescriptor] { throw RepositoryError.unavailable }
    func upsertCustomBrowser(_: BrowserDescriptor) throws { throw RepositoryError.unavailable }
    func deleteCustomBrowser(id _: BrowserID) throws { throw RepositoryError.unavailable }

    func load() throws -> AppSettings { throw RepositoryError.unavailable }
    func save(_: AppSettings) throws { throw RepositoryError.unavailable }
}

private actor SessionPendingRequestStore: PendingRequestStore {
    private var snapshot = PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])

    func load() async throws -> PendingRequestSnapshot {
        snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        self.snapshot = snapshot
    }
}

private actor UnavailablePendingRequestStore: PendingRequestStore {
    private enum StoreError: Error {
        case unavailable
    }

    func load() async throws -> PendingRequestSnapshot {
        throw StoreError.unavailable
    }

    func save(_: PendingRequestSnapshot) async throws {
        throw StoreError.unavailable
    }
}
