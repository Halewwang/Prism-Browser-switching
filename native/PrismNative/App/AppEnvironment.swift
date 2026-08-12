import Observation
import PrismCore

@MainActor
@Observable
final class AppEnvironment: PersistenceWarningPresenting {
    let route: AppRoute
    private(set) var unmatchedBehavior: UnmatchedBehavior
    let updateChecker: any UpdateChecking
    let ruleRepository: any RuleRepository
    let historyRepository: any HistoryRepository
    let browserPreferenceRepository: any BrowserPreferenceRepository
    let settingsRepository: any SettingsRepository
    private(set) var persistenceWarnings: [PersistenceWarning]
    private(set) var linkRoutingCoordinator: LinkRoutingCoordinator?
    private(set) var linkIntakeService: LinkIntakeService?
    private(set) var defaultBrowserService: DefaultBrowserService?
    private(set) var loginItemService: LoginItemService?

    init(
        route: AppRoute,
        unmatchedBehavior: UnmatchedBehavior,
        updateChecker: any UpdateChecking,
        ruleRepository: any RuleRepository,
        historyRepository: any HistoryRepository,
        browserPreferenceRepository: any BrowserPreferenceRepository,
        settingsRepository: any SettingsRepository,
        persistenceWarnings: [PersistenceWarning] = []
    ) {
        self.route = route
        self.unmatchedBehavior = unmatchedBehavior
        self.updateChecker = updateChecker
        self.ruleRepository = ruleRepository
        self.historyRepository = historyRepository
        self.browserPreferenceRepository = browserPreferenceRepository
        self.settingsRepository = settingsRepository
        self.persistenceWarnings = persistenceWarnings
        linkRoutingCoordinator = nil
        linkIntakeService = nil
        defaultBrowserService = nil
        loginItemService = nil
    }

    static let preview = AppEnvironment(
        route: .history,
        unmatchedBehavior: .alwaysAsk,
        updateChecker: DisabledUpdateChecker(),
        ruleRepository: InMemoryRuleRepository(),
        historyRepository: InMemoryHistoryRepository(),
        browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
        settingsRepository: InMemorySettingsRepository()
    )

    @discardableResult
    func restoreAndReconcile(
        queue: LinkRequestQueue,
        warningSource: (any PersistenceWarningSource)?
    ) async -> Bool {
        do {
            try await queue.restore()
        } catch {
            addWarning(.recoveryStoreUnavailable)
            return false
        }

        if let warningSource {
            for warning in await warningSource.drainPersistenceWarnings() {
                addWarning(warning)
            }
        }

        let settings: AppSettings
        do {
            settings = try settingsRepository.load()
            unmatchedBehavior = settings.unmatchedBehavior
        } catch {
            addWarning(.settingsNotSaved)
            var safeSettings = AppSettings.defaults
            safeSettings.automaticRulesEnabled = false
            safeSettings.unmatchedBehavior = .alwaysAsk
            settings = safeSettings
            unmatchedBehavior = safeSettings.unmatchedBehavior
        }

        for terminalRecord in await queue.terminalSnapshot() {
            if settings.historyEnabled, let historyEntry = terminalRecord.historyEntry {
                do {
                    try historyRepository.upsert(historyEntry)
                } catch {
                    addWarning(.historyNotSaved)
                    continue
                }
            }

            do {
                try await queue.compactTerminal(terminalRecord.requestID)
            } catch {
                addWarning(.recoveryStoreUnavailable)
            }
        }
        return true
    }

    func connectLinkRouting(
        coordinator: LinkRoutingCoordinator,
        intake: LinkIntakeService,
        defaultBrowserService: DefaultBrowserService?,
        loginItemService: LoginItemService?
    ) {
        precondition(linkRoutingCoordinator == nil && linkIntakeService == nil)
        linkRoutingCoordinator = coordinator
        linkIntakeService = intake
        self.defaultBrowserService = defaultBrowserService
        self.loginItemService = loginItemService
    }

    func present(_ warning: PersistenceWarning) {
        addWarning(warning)
    }

    private func addWarning(_ warning: PersistenceWarning) {
        guard !persistenceWarnings.contains(warning) else { return }
        persistenceWarnings.append(warning)
    }
}
