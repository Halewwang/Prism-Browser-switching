import Foundation
import PrismCore

typealias RecoveryPendingRequestStore = any PendingRequestStore & PersistenceWarningSource

@MainActor
private final class ReconnectablePendingRequestStore: PendingRequestStore, PersistenceWarningSource {
    typealias Factory = @MainActor @Sendable () throws -> RecoveryPendingRequestStore

    private let factory: Factory
    private var backing: RecoveryPendingRequestStore?

    init(factory: @escaping Factory) {
        self.factory = factory
    }

    func load() async throws -> PendingRequestSnapshot {
        try await resolveBacking().load()
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        try await resolveBacking().save(snapshot)
    }

    func drainPersistenceWarnings() async -> [PersistenceWarning] {
        guard let backing else { return [] }
        return await backing.drainPersistenceWarnings()
    }

    private func resolveBacking() throws -> RecoveryPendingRequestStore {
        if let backing { return backing }
        let created = try factory()
        backing = created
        return created
    }
}

@MainActor
final class ProductionAppComposition {
    private enum RestorationState {
        case notStarted
        case restoring(id: UUID, task: Task<Bool, Never>)
        case failed
        case succeeded
    }

    let environment: AppEnvironment
    let recoveryQueue: LinkRequestQueue
    let bootstrapBuffer: BootstrapLinkBuffer
    let linkRoutingCoordinator: LinkRoutingCoordinator
    let linkIntakeService: LinkIntakeService
    let defaultBrowserService: DefaultBrowserService
    let loginItemService: LoginItemService
    let selectorPresentationRelay: SelectorPresentationRelay
    let activationTracker: ApplicationActivationTracker
    let mainWindowOpening: MainWindowOpening
    let browserCatalog: any BrowserCataloging
    let sourceManifest: SourceSupportManifest
    let operatingSystemVersion: OperatingSystemVersion
    let selectorSessionFactory: SelectorSessionFactory
    let windowCoordinator: WindowCoordinator
    let routingOutcomeCenter: LinkRoutingOutcomeCenter
    let onboardingTestLinkRouter: OnboardingTestLinkRouter

    private let warningSource: (any PersistenceWarningSource)?
    private var restorationState = RestorationState.notStarted
    private var didFinishRestoration = false
    private var didFinishLaunching = false
    private(set) var finishLaunchCount = 0

    var runtimeLinkRecoveryState: RuntimeLinkRecoveryState {
        let state = environment.runtimeLinkRecoveryState
        if state == .routingResumeRequired, !environment.settings.onboardingCompleted {
            return .none
        }
        return state
    }

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
        activationTracker: ApplicationActivationTracker? = nil,
        mainWindowOpening: MainWindowOpening? = nil,
        browserCatalog: (any BrowserCataloging)? = nil,
        sourceManifest: SourceSupportManifest = .disabled,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        iconProvider: (any ApplicationIconProviding)? = nil,
        selectorSessionFactory: SelectorSessionFactory? = nil,
        windowCoordinator: WindowCoordinator? = nil,
        routingOutcomeCenter: LinkRoutingOutcomeCenter? = nil
    ) {
        let relay = selectorPresentationRelay ?? SelectorPresentationRelay()
        let opening = mainWindowOpening ?? MainWindowOpening { [weak environment] route in
            environment?.updateRoute(route)
        }
        let catalog = browserCatalog ?? BrowserCatalogService(
            browserPreferences: environment.browserPreferenceRepository
        )
        let pendingCountProvider = RecoveryQueuePendingCountProvider(queue: recoveryQueue)
        let navigationHandler = AppSelectorNavigationHandler(
            environment: environment,
            mainWindowOpening: opening
        )
        let sessions = selectorSessionFactory ?? SelectorSessionFactory(
            browserCatalog: catalog,
            routingCoordinator: linkRoutingCoordinator,
            pendingCountProvider: pendingCountProvider,
            navigationHandler: navigationHandler,
            iconProvider: iconProvider ?? ApplicationIconProvider(),
            sourceManifest: sourceManifest,
            operatingSystemVersion: operatingSystemVersion
        )
        let windows = windowCoordinator ?? WindowCoordinator(
            mainWindowOpening: opening,
            contentProvider: sessions
        )
        let outcomes = routingOutcomeCenter ?? LinkRoutingOutcomeCenter()
        linkRoutingCoordinator.connectOutcomeReporter(outcomes)

        self.environment = environment
        self.recoveryQueue = recoveryQueue
        self.warningSource = warningSource
        self.bootstrapBuffer = bootstrapBuffer
        self.linkRoutingCoordinator = linkRoutingCoordinator
        self.linkIntakeService = linkIntakeService
        self.defaultBrowserService = defaultBrowserService
        self.loginItemService = loginItemService
        self.selectorPresentationRelay = relay
        self.activationTracker = activationTracker ?? ApplicationActivationTracker()
        self.mainWindowOpening = opening
        self.browserCatalog = catalog
        self.sourceManifest = sourceManifest
        self.operatingSystemVersion = operatingSystemVersion
        self.selectorSessionFactory = sessions
        self.windowCoordinator = windows
        self.routingOutcomeCenter = outcomes
        self.onboardingTestLinkRouter = OnboardingTestLinkRouter(
            intake: linkIntakeService,
            coordinator: linkRoutingCoordinator,
            outcomes: outcomes
        )
        relay.target = windows
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
        let sourceManifest = SourceSupportManifest.disabled
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        let coordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: environment.ruleRepository,
            historyRepository: environment.historyRepository,
            historyService: environment.historyService,
            settingsRepository: environment.settingsRepository,
            browserCatalog: catalog,
            browserLauncher: BrowserLauncherService(),
            sourceManifest: sourceManifest,
            operatingSystemVersion: operatingSystemVersion,
            presenter: relay,
            warningPresenter: environment
        )
        let intake = LinkIntakeService(
            queue: queue,
            bootstrap: bootstrap,
            sourceAttributor: SourceAttributionProvider(processAncestry: SystemProcessAncestry()),
            lastActivatedSource: { [weak tracker] in tracker?.lastActivatedApplication },
            coordinator: coordinator,
            warningPresenter: environment
        )
        coordinator.continuationRequester = intake
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
            activationTracker: tracker,
            browserCatalog: catalog,
            sourceManifest: sourceManifest,
            operatingSystemVersion: operatingSystemVersion
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
        recoveryStoreFactory: @escaping @MainActor @Sendable () throws -> RecoveryPendingRequestStore
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
        await restore(retryFailed: false)
    }

    @discardableResult
    func retryPendingTerminalHistory() async -> Bool {
        await environment.retryPendingTerminalHistory(queue: recoveryQueue)
    }

    func finishLaunchingOnce() async {
        guard !didFinishLaunching else { return }
        didFinishLaunching = true
        finishLaunchCount += 1
        guard await restoreOnce() else { return }
        await finishRestoration(
            allowAutomaticRouting: environment.settings.onboardingCompleted
        )
    }

    @discardableResult
    func retryRestorationAfterUserAction() async -> Bool {
        guard await restore(retryFailed: true) else { return false }
        await finishRestoration(allowAutomaticRouting: false)
        if environment.settings.onboardingCompleted {
            await linkIntakeService.waitForPersistenceForTesting()
            _ = await linkIntakeService.resumeRoutingAfterRecoveryUserAction()
        }
        return true
    }

    @discardableResult
    func retryPendingPersistenceAfterUserAction() async -> Bool {
        guard didFinishRestoration else { return false }
        return await linkIntakeService.retryPendingPersistenceAfterUserAction()
    }

    @discardableResult
    func resumeRoutingAfterRecoveryUserAction() async -> Bool {
        guard didFinishRestoration, environment.settings.onboardingCompleted else { return false }
        return await linkIntakeService.resumeRoutingAfterRecoveryUserAction()
    }

    func resumeRoutingAfterOnboardingCompletion() async {
        guard didFinishRestoration, environment.settings.onboardingCompleted else {
            return
        }
        await linkIntakeService.resumeRoutingAfterRecoveryUserAction()
    }

    private func restore(retryFailed: Bool) async -> Bool {
        switch restorationState {
        case .succeeded:
            return true
        case let .restoring(id, task):
            return await settleRestoration(id: id, task: task)
        case .failed where !retryFailed:
            return false
        case .notStarted, .failed:
            break
        }

        let environment = environment
        let queue = recoveryQueue
        let warningSource = warningSource
        let id = UUID()
        let task = Task { @MainActor in
            await environment.restoreAndReconcile(
                queue: queue,
                warningSource: warningSource
            )
        }
        restorationState = .restoring(id: id, task: task)
        return await settleRestoration(id: id, task: task)
    }

    private func settleRestoration(id: UUID, task: Task<Bool, Never>) async -> Bool {
        let succeeded = await task.value
        if case let .restoring(currentID, _) = restorationState, currentID == id {
            restorationState = succeeded ? .succeeded : .failed
        }
        return succeeded
    }

    private func finishRestoration(allowAutomaticRouting: Bool) async {
        guard !didFinishRestoration else {
            if allowAutomaticRouting {
                await linkIntakeService.resumeRoutingAfterRecoveryUserAction()
            }
            return
        }
        didFinishRestoration = true
        linkIntakeService.finishRestorationAndStartDraining(
            routeAfterDraining: allowAutomaticRouting
        )
    }

    private static func make(
        bootstrapBuffer: BootstrapLinkBuffer,
        diagnosticRecorder: (@MainActor (LinkCaptureDiagnostic) -> Void)?,
        modelContainerFactory: @escaping @MainActor () throws -> ModelContainerResult,
        recoveryStoreFactory: @escaping @MainActor @Sendable () throws -> RecoveryPendingRequestStore
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

        let reconnectableStore = ReconnectablePendingRequestStore(factory: recoveryStoreFactory)
        let queue = LinkRequestQueue(store: reconnectableStore)
        let warningSource: (any PersistenceWarningSource)? = reconnectableStore

        let environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: UpdateCheckerFactory.makeIfConfigured(),
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
        let sourceAttributor = SourceAttributionProvider(processAncestry: SystemProcessAncestry())
        let sourceManifest = SourceSupportManifest.bundled()
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        let coordinator = LinkRoutingCoordinator(
            queue: queue,
            ruleRepository: repositories.rules,
            historyRepository: repositories.history,
            historyService: environment.historyService,
            settingsRepository: repositories.settings,
            browserCatalog: catalog,
            browserLauncher: launcher,
            sourceManifest: sourceManifest,
            operatingSystemVersion: operatingSystemVersion,
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
        coordinator.continuationRequester = intake
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
            activationTracker: tracker,
            browserCatalog: catalog,
            sourceManifest: sourceManifest,
            operatingSystemVersion: operatingSystemVersion,
            iconProvider: ApplicationIconProvider(workspace: workspace)
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
    func upsertAndEnforceRetention(_: HistoryEntry, limit _: Int, cutoff _: Date) throws {
        throw RepositoryError.unavailable
    }
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
