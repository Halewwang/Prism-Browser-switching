import Observation
import PrismCore

@MainActor
@Observable
final class AppEnvironment {
    let route: AppRoute
    private(set) var unmatchedBehavior: UnmatchedBehavior
    let updateChecker: any UpdateChecking
    let ruleRepository: any RuleRepository
    let historyRepository: any HistoryRepository
    let browserPreferenceRepository: any BrowserPreferenceRepository
    let settingsRepository: any SettingsRepository
    private(set) var persistenceWarnings: [PersistenceWarning]

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

    func restoreAndReconcile(
        queue: LinkRequestQueue,
        warningSource: (any PersistenceWarningSource)?
    ) async {
        do {
            try await queue.restore()
        } catch {
            addWarning(.recoveryStoreUnavailable)
            return
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
    }

    private func addWarning(_ warning: PersistenceWarning) {
        guard !persistenceWarnings.contains(warning) else { return }
        persistenceWarnings.append(warning)
    }
}
