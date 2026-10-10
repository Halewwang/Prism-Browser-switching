import Foundation
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

    @Test func resetRestoresOptionsWithoutRepeatingOnboardingOrPruningExistingHistory() async throws {
        let fixture = StartupPhaseFixture(onboardingCompleted: true)
        #expect(await fixture.restore())
        #expect(fixture.environment.mutateSettings {
            $0.language = .english
            $0.automaticRulesEnabled = false
            $0.showMenuBarItem = false
            $0.unmatchedBehavior = .preferredBrowser
            $0.preferredBrowserID = "browser"
            $0.lastUsedBrowserID = "browser"
            $0.historyLimit = 500
            $0.historyRetentionDays = 365
        })
        let date = Date.now.addingTimeInterval(-90 * 24 * 60 * 60)
        let rule = RoutingRule(
            id: UUID(), isEnabled: true, matcher: .exactHost("example.com"),
            targetBrowserID: "browser", priority: 0, label: nil,
            createdAt: date, updatedAt: date
        )
        try fixture.environment.ruleRepository.upsert(rule)
        for _ in 0..<105 {
            let id = UUID()
            try fixture.environment.historyRepository.upsert(HistoryEntry(
                id: id, requestID: id, sanitizedURL: URL(string: "https://example.com"),
                sourceBundleIdentifier: nil, sourceDisplayName: "Unknown",
                targetBrowserID: "browser", targetDisplayName: "Browser",
                method: .manual, result: .success, matchingRuleID: nil,
                failureReason: nil, attemptCount: 1, createdAt: date, completedAt: date
            ))
        }

        #expect(fixture.environment.resetSettingsToDefaults())

        var expected = AppSettings.defaults
        expected.onboardingCompleted = true
        expected.historyLimit = 500
        expected.historyRetentionDays = 365
        #expect(fixture.environment.settings == expected)
        #expect(try fixture.settings.load() == expected)
        #expect(fixture.environment.startupPhase == .shell)
        #expect(try fixture.environment.ruleRepository.all() == [rule])
        #expect(try await fixture.environment.historyService.loadRecent(settings: expected).count == 105)
    }

    @Test func failedResetRetainsTheSavedOptionsAndReportsThePersistenceWarning() async {
        let fixture = StartupPhaseFixture(onboardingCompleted: true)
        #expect(await fixture.restore())
        #expect(fixture.environment.mutateSettings { $0.automaticRulesEnabled = false })
        let before = fixture.environment.settings
        fixture.settings.saveFails = true

        #expect(!fixture.environment.resetSettingsToDefaults())

        #expect(fixture.environment.settings == before)
        #expect(fixture.environment.startupPhase == .shell)
        #expect(fixture.environment.persistenceWarnings.contains(.settingsNotSaved))
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
