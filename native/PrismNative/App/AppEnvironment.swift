import Foundation
import Observation
import PrismCore

extension AppSettings {
    static let conservativePersistenceFallback = AppSettings(
        language: .system,
        unmatchedBehavior: .alwaysAsk,
        preferredBrowserID: nil,
        lastUsedBrowserID: nil,
        historyEnabled: false,
        historyLimit: 0,
        historyRetentionDays: 0,
        automaticRulesEnabled: false,
        showMenuBarItem: false,
        onboardingCompleted: false,
        schemaVersion: AppSettings.defaults.schemaVersion
    )
}

enum AppStartupPhase: Equatable, Sendable {
    case loading
    case onboarding
    case shell
    case recovery
}

@MainActor
@Observable
final class AppEnvironment: RuntimeLinkPersistenceWarningPresenting {
    private enum PersistenceWarningOrigin {
        case independent
        case startupRestoration
    }

    private struct TerminalHistoryReconciliationFlight {
        let id: UUID
        let task: Task<Bool, Never>
    }

    private(set) var route: AppRoute
    private(set) var pendingSelectorRulePrefill: SelectorRulePrefill?
    private(set) var pendingBrowserManagement = false
    private(set) var unmatchedBehavior: UnmatchedBehavior
    private(set) var settings: AppSettings
    private(set) var startupPhase: AppStartupPhase
    let updateChecker: any UpdateChecking
    let ruleRepository: any RuleRepository
    let historyRepository: any HistoryRepository
    let historyService: HistoryService
    let browserPreferenceRepository: any BrowserPreferenceRepository
    let settingsRepository: any SettingsRepository
    private(set) var persistenceWarnings: [PersistenceWarning]
    private(set) var hasPendingTerminalHistoryReconciliation: Bool
    private(set) var runtimeLinkRecoveryState: RuntimeLinkRecoveryState
    private(set) var linkRoutingCoordinator: LinkRoutingCoordinator?
    private(set) var linkIntakeService: LinkIntakeService?
    private(set) var defaultBrowserService: DefaultBrowserService?
    private(set) var loginItemService: LoginItemService?
    @ObservationIgnored
    private var terminalHistoryReconciliationFlight: TerminalHistoryReconciliationFlight?
    @ObservationIgnored
    private var startupRestorationOwnsRecoveryStoreWarning: Bool

    init(
        route: AppRoute,
        unmatchedBehavior: UnmatchedBehavior,
        updateChecker: any UpdateChecking,
        ruleRepository: any RuleRepository,
        historyRepository: any HistoryRepository,
        historyService: HistoryService? = nil,
        browserPreferenceRepository: any BrowserPreferenceRepository,
        settingsRepository: any SettingsRepository,
        persistenceWarnings: [PersistenceWarning] = []
    ) {
        self.route = route
        pendingSelectorRulePrefill = nil
        var initialSettings = AppSettings.conservativePersistenceFallback
        initialSettings.unmatchedBehavior = unmatchedBehavior
        self.unmatchedBehavior = unmatchedBehavior
        settings = initialSettings
        startupPhase = .loading
        self.updateChecker = updateChecker
        self.ruleRepository = ruleRepository
        self.historyRepository = historyRepository
        self.historyService = historyService ?? HistoryService(repository: historyRepository)
        self.browserPreferenceRepository = browserPreferenceRepository
        self.settingsRepository = settingsRepository
        self.persistenceWarnings = persistenceWarnings
        hasPendingTerminalHistoryReconciliation = false
        runtimeLinkRecoveryState = .none
        linkRoutingCoordinator = nil
        linkIntakeService = nil
        defaultBrowserService = nil
        loginItemService = nil
        terminalHistoryReconciliationFlight = nil
        startupRestorationOwnsRecoveryStoreWarning = false
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

    /// Applies a settings change to the latest durable value before exposing it to the UI.
    /// This keeps independent settings actions from overwriting one another.
    @discardableResult
    func mutateSettings(_ transform: (inout AppSettings) -> Void) -> Bool {
        do {
            var updated = try settingsRepository.load()
            transform(&updated)
            try settingsRepository.save(updated)
            settings = updated
            unmatchedBehavior = updated.unmatchedBehavior
            if startupPhase == .onboarding || startupPhase == .shell {
                startupPhase = updated.onboardingCompleted ? .shell : .onboarding
            }
            clearWarning(.settingsNotSaved)
            return true
        } catch {
            addWarning(.settingsNotSaved)
            return false
        }
    }

    @discardableResult
    func restoreAndReconcile(
        queue: LinkRequestQueue,
        warningSource: (any PersistenceWarningSource)?
    ) async -> Bool {
        let settingsResult = loadSettingsForRestoration()

        do {
            try await queue.restore(
                discardTerminalHistory: !settingsResult.isAvailable || !settingsResult.settings.historyEnabled
            )
        } catch {
            addWarning(.recoveryStoreUnavailable, origin: .startupRestoration)
            hasPendingTerminalHistoryReconciliation = false
            startupPhase = .recovery
            return false
        }

        if let warningSource {
            for warning in await warningSource.drainPersistenceWarnings() {
                addWarning(warning)
            }
        }

        _ = await reconcilePendingTerminalHistory(
            queue: queue,
            settings: settingsResult.isAvailable ? settingsResult.settings : nil
        )
        resolveStartupRestorationWarning()
        startupPhase = settingsResult.isAvailable && settingsResult.settings.onboardingCompleted
            ? .shell
            : .onboarding
        return true
    }

    /// Retries only durable terminal-history reconciliation. It never resumes link routing
    /// or replays a browser handoff, and concurrent user actions share the same attempt.
    @discardableResult
    func retryPendingTerminalHistory(queue: LinkRequestQueue) async -> Bool {
        if let terminalHistoryReconciliationFlight {
            return await terminalHistoryReconciliationFlight.task.value
        }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            guard let latestSettings = self.loadLatestSettingsForReconciliation() else {
                self.hasPendingTerminalHistoryReconciliation = !(await queue.terminalSnapshot()).isEmpty
                return false
            }
            return await self.reconcilePendingTerminalHistory(
                queue: queue,
                settings: latestSettings
            )
        }
        terminalHistoryReconciliationFlight = TerminalHistoryReconciliationFlight(id: id, task: task)

        let succeeded = await task.value
        if terminalHistoryReconciliationFlight?.id == id {
            terminalHistoryReconciliationFlight = nil
        }
        return succeeded
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

    func updateRoute(_ route: AppRoute) {
        self.route = route
    }

    func stageSelectorRulePrefill(_ prefill: SelectorRulePrefill) {
        pendingSelectorRulePrefill = prefill
        route = .rules
    }

    func consumeSelectorRulePrefill() -> SelectorRulePrefill? {
        defer { pendingSelectorRulePrefill = nil }
        return pendingSelectorRulePrefill
    }

    func stageBrowserManagement() {
        pendingBrowserManagement = true
        route = .settings
    }

    func consumeBrowserManagement() -> Bool {
        defer { pendingBrowserManagement = false }
        return pendingBrowserManagement
    }

    func present(_ warning: PersistenceWarning) {
        addWarning(warning)
    }

    func updateRuntimeLinkRecoveryState(_ state: RuntimeLinkRecoveryState) {
        runtimeLinkRecoveryState = state
    }

    private func loadSettingsForRestoration() -> (settings: AppSettings, isAvailable: Bool) {
        do {
            let loaded = try settingsRepository.load()
            applyLoadedSettings(loaded)
            return (loaded, true)
        } catch {
            var fallback = AppSettings.conservativePersistenceFallback
            fallback.unmatchedBehavior = .alwaysAsk
            settings = fallback
            unmatchedBehavior = .alwaysAsk
            addWarning(.settingsNotSaved)
            return (fallback, false)
        }
    }

    private func loadLatestSettingsForReconciliation() -> AppSettings? {
        do {
            let loaded = try settingsRepository.load()
            applyLoadedSettings(loaded)
            return loaded
        } catch {
            addWarning(.settingsNotSaved)
            return nil
        }
    }

    private func applyLoadedSettings(_ loaded: AppSettings) {
        settings = loaded
        unmatchedBehavior = loaded.unmatchedBehavior
    }

    private func reconcilePendingTerminalHistory(
        queue: LinkRequestQueue,
        settings: AppSettings?
    ) async -> Bool {
        guard let settings else {
            hasPendingTerminalHistoryReconciliation = !(await queue.terminalSnapshot()).isEmpty
            return false
        }

        _ = await historyService.reconcile(
            queue: queue,
            settings: settings,
            warning: { [weak self] warning in self?.addWarning(warning) }
        )
        hasPendingTerminalHistoryReconciliation = !(await queue.terminalSnapshot()).isEmpty
        return !hasPendingTerminalHistoryReconciliation
    }

    private func addWarning(
        _ warning: PersistenceWarning,
        origin: PersistenceWarningOrigin = .independent
    ) {
        if warning == .recoveryStoreUnavailable {
            switch origin {
            case .independent:
                startupRestorationOwnsRecoveryStoreWarning = false
            case .startupRestoration:
                if !persistenceWarnings.contains(warning) {
                    startupRestorationOwnsRecoveryStoreWarning = true
                }
            }
        }
        guard !persistenceWarnings.contains(warning) else { return }
        persistenceWarnings.append(warning)
    }

    private func resolveStartupRestorationWarning() {
        guard startupRestorationOwnsRecoveryStoreWarning else { return }
        startupRestorationOwnsRecoveryStoreWarning = false
        clearWarning(.recoveryStoreUnavailable)
    }

    private func clearWarning(_ warning: PersistenceWarning) {
        persistenceWarnings.removeAll { $0 == warning }
    }
}
