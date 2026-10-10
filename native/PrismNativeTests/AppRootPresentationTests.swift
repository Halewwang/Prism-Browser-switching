import AppKit
import PrismCore
import SwiftUI
import Testing
@testable import PrismNative

@Suite("App root presentation")
struct AppRootPresentationTests {
    @Test @MainActor func managementWindowUsesFixedContentBounds() async {
        let composition = DebugAppFixture.make(
            bootstrapBuffer: BootstrapLinkBuffer(), variant: .history
        ).composition
        await composition.finishLaunchingOnce()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hostingView = NSHostingView(rootView: AppRootView(composition: composition, systemActions: .inert))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let expectedSize = NSSize(width: 1120, height: 900)
        #expect(window.contentMinSize == expectedSize)
        #expect(window.contentMaxSize == expectedSize)
        #expect(window.contentView?.frame.size == expectedSize)
    }

    @Test(arguments: [
        (phase: AppStartupPhase.loading, expected: AppRootKind.loading),
        (phase: AppStartupPhase.onboarding, expected: AppRootKind.onboarding),
        (phase: AppStartupPhase.shell, expected: AppRootKind.shell),
        (phase: AppStartupPhase.recovery, expected: AppRootKind.recovery),
    ])
    func everyStartupPhaseMapsToItsMatchingRoot(
        phase: AppStartupPhase,
        expected: AppRootKind
    ) {
        let presentation = AppRootPresentation(
            startupPhase: phase,
            hasPendingTerminalHistoryReconciliation: false,
            persistenceWarnings: []
        )

        #expect(presentation.kind == expected)
    }

    @Test func phasesWithoutARecoveryConditionHaveNoRecoveryAction() {
        for phase in [AppStartupPhase.loading, .onboarding, .shell] {
            let presentation = AppRootPresentation(
                startupPhase: phase,
                hasPendingTerminalHistoryReconciliation: false,
                persistenceWarnings: []
            )

            #expect(presentation.recovery == nil)
        }
    }
}

@Suite("Shared app route binding")
@MainActor
struct SharedAppRouteBindingTests {
    @Test func bindingReadsAndWritesTheSingleEnvironmentRoute() {
        let environment = makeRootPresentationEnvironment(route: .history)
        let binding = environment.sharedRouteBinding

        #expect(binding.wrappedValue == .history)

        binding.wrappedValue = .settings

        #expect(environment.route == .settings)

        environment.updateRoute(.rules)

        #expect(binding.wrappedValue == .rules)
    }
}

@Suite("App recovery presentation")
struct AppRecoveryPresentationTests {
    @Test func pendingTerminalHistoryHasHighestPriority() throws {
        let presentation = try #require(recovery(
            startupPhase: .recovery,
            hasPendingTerminalHistoryReconciliation: true,
            warnings: [.recoveryStoreUnavailable, .historyNotSaved]
        ))

        #expect(presentation.reason == .pendingTerminalHistory)
        #expect(presentation.primaryAction.action == .retryHistory)
        #expect(presentation.actions.count == 1)
    }

    @Test func volatileBufferedLinkPersistenceTakesPriorityOverDurablePendingHistory() throws {
        let presentation = try #require(recovery(
            startupPhase: .shell,
            hasPendingTerminalHistoryReconciliation: true,
            runtimeLinkRecoveryState: .persistenceRetryRequired,
            warnings: [.historyNotSaved, .recoveryStoreUnavailable]
        ))

        #expect(presentation.reason == .runtimePendingPersistence)
        #expect(presentation.primaryAction.action == .retryPendingPersistence)
        #expect(presentation.actions.count == 1)
    }

    @Test func startupRecoveryRetriesRestorationBeforeRuntimeWarnings() throws {
        let presentation = try #require(recovery(
            startupPhase: .recovery,
            warnings: [.recoveryStoreUnavailable, .settingsNotSaved]
        ))

        #expect(presentation.reason == .startupRestoration)
        #expect(presentation.primaryAction.action == .retryRestoration)
        #expect(presentation.actions.count == 1)
    }

    @Test func pausedRuntimePersistenceOffersASafePersistenceOnlyRetry() throws {
        let presentation = try #require(recovery(
            startupPhase: .shell,
            runtimeLinkRecoveryState: .persistenceRetryRequired,
            warnings: [.recoveryStoreUnavailable]
        ))

        #expect(presentation.reason == .runtimePendingPersistence)
        #expect(presentation.primaryAction.action == .retryPendingPersistence)
        #expect(presentation.primaryAction.title == "Retry Saving Link")
        #expect(presentation.actions.count == 1)
    }

    @Test func persistedRuntimeLinksRequireAnExplicitRoutingResume() throws {
        let presentation = try #require(recovery(
            startupPhase: .shell,
            runtimeLinkRecoveryState: .routingResumeRequired,
            warnings: []
        ))

        #expect(presentation.reason == .runtimeRoutingPaused)
        #expect(presentation.primaryAction.action == .resumeRouting)
        #expect(presentation.primaryAction.title == "Resume Link Handling")
        #expect(presentation.actions.count == 1)
    }

    @Test func ordinaryHistoryWarningNeverMasqueradesAsPendingReconciliation() throws {
        let presentation = try #require(recovery(
            startupPhase: .shell,
            warnings: [.historyNotSaved]
        ))

        #expect(presentation.reason == .historyNotSaved)
        #expect(presentation.reason != .pendingTerminalHistory)
        #expect(presentation.primaryAction.action == .restart)
        #expect(presentation.actions.count == 1)
    }

    @Test func settingsWarningUsesTheSafestNonSuccessAction() throws {
        let presentation = try #require(recovery(
            startupPhase: .shell,
            warnings: [.settingsNotSaved]
        ))

        #expect(presentation.reason == .settingsNotSaved)
        #expect(presentation.primaryAction.action == .restart)
        #expect(presentation.actions.count == 1)
    }

    @Test func recoveredCorruptStoreKeepsItsBackupIdentityAndRequiresRestart() throws {
        let presentation = try #require(recovery(
            startupPhase: .shell,
            warnings: [.corruptStoreRecovered(backupLocation: "/tmp/prism-backup")]
        ))

        #expect(presentation.reason == .corruptStoreRecovered(backupLocation: "/tmp/prism-backup"))
        #expect(presentation.primaryAction.action == .restart)
        #expect(presentation.actions.count == 1)
    }

    @Test func runtimeStorageFailureWinsOverOtherWarnings() throws {
        let presentation = try #require(recovery(
            startupPhase: .shell,
            warnings: [
                .settingsNotSaved,
                .historyNotSaved,
                .corruptStoreRecovered(backupLocation: "/tmp/prism-backup"),
                .recoveryStoreUnavailable,
            ]
        ))

        #expect(presentation.reason == .runtimeStorageUnavailable)
        #expect(presentation.primaryAction.action == .restart)
        #expect(presentation.actions.count == 1)
    }

    @Test func noRecoveryConditionProducesNoAction() {
        #expect(recovery(startupPhase: .shell, warnings: []) == nil)
    }

    private func recovery(
        startupPhase: AppStartupPhase,
        hasPendingTerminalHistoryReconciliation: Bool = false,
        runtimeLinkRecoveryState: RuntimeLinkRecoveryState = .none,
        warnings: [PersistenceWarning]
    ) -> AppRecoveryPresentation? {
        AppRootPresentation(
            startupPhase: startupPhase,
            hasPendingTerminalHistoryReconciliation: hasPendingTerminalHistoryReconciliation,
            runtimeLinkRecoveryState: runtimeLinkRecoveryState,
            persistenceWarnings: warnings
        ).recovery
    }
}

@Suite("Startup restoration warning origin")
@MainActor
struct StartupRestorationWarningOriginTests {
    @Test func successfulRetryRemovesOnlyTheStartupOwnedWarningAndDoesNotShowRestart() async {
        let fixture = StartupRestorationWarningFixture()

        #expect(!(await fixture.restore()))
        #expect(fixture.presentation.recovery?.primaryAction.action == .retryRestoration)

        #expect(await fixture.restore())

        #expect(fixture.environment.startupPhase == .shell)
        #expect(!fixture.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
        #expect(fixture.presentation.recovery == nil)
        #expect(fixture.environment.route == .history)
    }

    @Test func preexistingRuntimeStorageWarningSurvivesAStartupRetry() async {
        let fixture = StartupRestorationWarningFixture(
            warnings: [.recoveryStoreUnavailable]
        )

        #expect(!(await fixture.restore()))
        #expect(await fixture.restore())

        #expect(fixture.environment.startupPhase == .shell)
        #expect(fixture.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
        #expect(fixture.presentation.recovery?.reason == .runtimeStorageUnavailable)
        #expect(fixture.presentation.recovery?.primaryAction.action == .restart)
    }

    @Test func independentlyReportedRuntimeStorageWarningSurvivesAStartupRetry() async {
        let fixture = StartupRestorationWarningFixture()

        #expect(!(await fixture.restore()))
        fixture.environment.present(.recoveryStoreUnavailable)
        #expect(await fixture.restore())

        #expect(fixture.environment.startupPhase == .shell)
        #expect(fixture.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
        #expect(fixture.presentation.recovery?.reason == .runtimeStorageUnavailable)
        #expect(fixture.presentation.recovery?.primaryAction.action == .restart)
    }

    @Test func successfulRetryNeverClearsUnrelatedWarnings() async {
        let warnings: [PersistenceWarning] = [
            .historyNotSaved,
            .settingsNotSaved,
            .corruptStoreRecovered(backupLocation: "/tmp/prism-backup"),
        ]
        let fixture = StartupRestorationWarningFixture(warnings: warnings)

        #expect(!(await fixture.restore()))
        #expect(await fixture.restore())

        for warning in warnings {
            #expect(fixture.environment.persistenceWarnings.contains(warning))
        }
        #expect(!fixture.environment.persistenceWarnings.contains(.recoveryStoreUnavailable))
        #expect(fixture.presentation.recovery?.reason ==
            .corruptStoreRecovered(backupLocation: "/tmp/prism-backup"))
        #expect(fixture.presentation.recovery?.primaryAction.action == .restart)
    }
}

@MainActor
private func makeRootPresentationEnvironment(route: AppRoute) -> AppEnvironment {
    AppEnvironment(
        route: route,
        unmatchedBehavior: .alwaysAsk,
        updateChecker: DisabledUpdateChecker(),
        ruleRepository: InMemoryRuleRepository(),
        historyRepository: InMemoryHistoryRepository(),
        browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
        settingsRepository: InMemorySettingsRepository()
    )
}

@MainActor
private struct StartupRestorationWarningFixture {
    let environment: AppEnvironment
    let queue: LinkRequestQueue

    init(warnings: [PersistenceWarning] = []) {
        var settings = AppSettings.defaults
        settings.onboardingCompleted = true
        environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: InMemoryRuleRepository(),
            historyRepository: InMemoryHistoryRepository(),
            browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
            settingsRepository: InMemorySettingsRepository(settings: settings),
            persistenceWarnings: warnings
        )
        queue = LinkRequestQueue(store: FailsFirstStartupRestorationStore())
    }

    var presentation: AppRootPresentation {
        AppRootPresentation(
            startupPhase: environment.startupPhase,
            hasPendingTerminalHistoryReconciliation: environment.hasPendingTerminalHistoryReconciliation,
            persistenceWarnings: environment.persistenceWarnings
        )
    }

    func restore() async -> Bool {
        await environment.restoreAndReconcile(queue: queue, warningSource: nil)
    }
}

private actor FailsFirstStartupRestorationStore: PendingRequestStore {
    private var loadCount = 0

    func load() throws -> PendingRequestSnapshot {
        loadCount += 1
        if loadCount == 1 {
            throw StartupRestorationWarningFixtureError.loadFailed
        }
        return PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])
    }

    func save(_ snapshot: PendingRequestSnapshot) throws {}
}

private enum StartupRestorationWarningFixtureError: Error {
    case loadFailed
}
