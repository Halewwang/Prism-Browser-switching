import PrismCore
import Testing
@testable import PrismNative

@Suite("App startup phase")
@MainActor
struct AppStartupPhaseTests {
    @Test func beginsInLoadingBeforeDurableStateIsRestored() {
        let fixture = StartupPhaseFixture(onboardingCompleted: true)

        #expect(fixture.environment.startupPhase == .loading)
    }

    @Test(arguments: [
        (completed: false, expected: AppStartupPhase.onboarding),
        (completed: true, expected: AppStartupPhase.shell),
    ])
    func successfulRestorationUsesTheDurableOnboardingFlag(
        completed: Bool,
        expected: AppStartupPhase
    ) async {
        let fixture = StartupPhaseFixture(onboardingCompleted: completed)

        #expect(await fixture.restore())

        #expect(fixture.environment.startupPhase == expected)
    }

    @Test func settingsLoadFailureFallsBackToOnboardingAndKeepsTheWarning() async {
        let fixture = StartupPhaseFixture(
            onboardingCompleted: true,
            settingsLoadFails: true
        )

        #expect(await fixture.restore())

        #expect(fixture.environment.startupPhase == .onboarding)
        #expect(fixture.environment.persistenceWarnings.contains(.settingsNotSaved))
    }

    @Test func queueRestoreFailureUsesRecoveryRegardlessOfDurableOnboardingState() async {
        let fixture = StartupPhaseFixture(
            onboardingCompleted: true,
            queueRestoreFails: true
        )

        #expect(!(await fixture.restore()))

        #expect(fixture.environment.startupPhase == .recovery)
        #expect(fixture.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
    }

    @Test func onboardingCompletionChangesToShellOnlyAfterTheSettingIsSaved() async {
        let fixture = StartupPhaseFixture(onboardingCompleted: false)
        #expect(await fixture.restore())
        #expect(fixture.environment.startupPhase == .onboarding)

        #expect(fixture.environment.mutateSettings { $0.onboardingCompleted = true })

        #expect(fixture.environment.startupPhase == .shell)
        #expect(fixture.settings.savedSettings?.onboardingCompleted == true)
    }

    @Test func failedOnboardingCompletionSaveDoesNotLeaveTheCurrentPhase() async {
        let fixture = StartupPhaseFixture(onboardingCompleted: false)
        #expect(await fixture.restore())
        fixture.settings.saveFails = true

        #expect(!fixture.environment.mutateSettings { $0.onboardingCompleted = true })

        #expect(fixture.environment.startupPhase == .onboarding)
        #expect(!fixture.environment.settings.onboardingCompleted)
    }

    @Test func ordinarySettingsMutationNeverChangesTheStartupPhase() async {
        let onboarding = StartupPhaseFixture(onboardingCompleted: false)
        #expect(await onboarding.restore())
        #expect(onboarding.environment.mutateSettings { $0.showMenuBarItem.toggle() })
        #expect(onboarding.environment.startupPhase == .onboarding)

        let shell = StartupPhaseFixture(onboardingCompleted: true)
        #expect(await shell.restore())
        #expect(shell.environment.mutateSettings { $0.automaticRulesEnabled.toggle() })
        #expect(shell.environment.startupPhase == .shell)
    }

    @Test func explicitlySavingOnboardingAsIncompleteReturnsToOnboarding() async {
        let fixture = StartupPhaseFixture(onboardingCompleted: true)
        #expect(await fixture.restore())
        #expect(fixture.environment.startupPhase == .shell)

        #expect(fixture.environment.mutateSettings { $0.onboardingCompleted = false })

        #expect(fixture.environment.startupPhase == .onboarding)
        #expect(fixture.settings.savedSettings?.onboardingCompleted == false)
    }
}

@MainActor
private struct StartupPhaseFixture {
    let environment: AppEnvironment
    let settings: StartupPhaseSettingsRepository
    let queue: LinkRequestQueue

    init(
        onboardingCompleted: Bool,
        settingsLoadFails: Bool = false,
        queueRestoreFails: Bool = false
    ) {
        var durableSettings = AppSettings.defaults
        durableSettings.onboardingCompleted = onboardingCompleted
        settings = StartupPhaseSettingsRepository(
            settings: durableSettings,
            loadFails: settingsLoadFails
        )
        environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: InMemoryRuleRepository(),
            historyRepository: InMemoryHistoryRepository(),
            browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
            settingsRepository: settings
        )
        queue = LinkRequestQueue(
            store: StartupPhasePendingStore(loadFails: queueRestoreFails)
        )
    }

    func restore() async -> Bool {
        await environment.restoreAndReconcile(queue: queue, warningSource: nil)
    }
}

@MainActor
private final class StartupPhaseSettingsRepository: SettingsRepository {
    private var settings: AppSettings
    var loadFails: Bool
    var saveFails = false
    private(set) var savedSettings: AppSettings?

    init(settings: AppSettings, loadFails: Bool) {
        self.settings = settings
        self.loadFails = loadFails
    }

    func load() throws -> AppSettings {
        if loadFails {
            throw StartupPhaseFixtureError.settingsLoadFailed
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        if saveFails {
            throw StartupPhaseFixtureError.settingsSaveFailed
        }
        self.settings = settings
        savedSettings = settings
    }
}

private actor StartupPhasePendingStore: PendingRequestStore {
    let loadFails: Bool

    init(loadFails: Bool) {
        self.loadFails = loadFails
    }

    func load() throws -> PendingRequestSnapshot {
        if loadFails {
            throw StartupPhaseFixtureError.queueRestoreFailed
        }
        return PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])
    }

    func save(_ snapshot: PendingRequestSnapshot) throws {}
}

private enum StartupPhaseFixtureError: Error {
    case settingsLoadFailed
    case settingsSaveFailed
    case queueRestoreFailed
}
