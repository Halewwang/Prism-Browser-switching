import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("Production app root coordinator")
@MainActor
struct AppRootCoordinatorTests {
    @Test func retainsOneOnboardingModelAndUsesTheSharedEnvironmentRoute() {
        let composition = makeRootComposition()
        let coordinator = AppRootCoordinator(
            composition: composition,
            systemActions: .inert
        )
        let originalModel = coordinator.onboardingModel

        #expect(coordinator.onboardingModel === originalModel)
        #expect(coordinator.presentation.kind == .loading)
        #expect(coordinator.routeBinding.wrappedValue == .overview)

        coordinator.routeBinding.wrappedValue = .settings

        #expect(composition.environment.route == .settings)
        #expect(coordinator.routeBinding.wrappedValue == .settings)
        #expect(coordinator.onboardingModel === originalModel)
    }

}

@Suite("Typed app root recovery actions")
@MainActor
struct AppRootRecoveryDispatcherTests {
    @Test func eachPresentationActionCallsOnlyItsMatchingRecoveryBoundary() async {
        let recorder = RootRecoveryRecorder()
        let dispatcher = AppRootRecoveryDispatcher(
            retryPendingTerminalHistory: {
                recorder.historyRetryCount += 1
                return true
            },
            retryRestoration: {
                recorder.restorationRetryCount += 1
                return false
            },
            retryPendingPersistence: {
                recorder.persistenceRetryCount += 1
                return true
            },
            resumeRouting: {
                recorder.routingResumeCount += 1
                return true
            },
            restart: {
                recorder.restartCount += 1
                return true
            }
        )

        #expect(await dispatcher.perform(.retryHistory))
        #expect(recorder.historyRetryCount == 1)
        #expect(recorder.restorationRetryCount == 0)
        #expect(recorder.restartCount == 0)

        #expect(!(await dispatcher.perform(.retryRestoration)))
        #expect(recorder.historyRetryCount == 1)
        #expect(recorder.restorationRetryCount == 1)
        #expect(recorder.restartCount == 0)

        #expect(await dispatcher.perform(.retryPendingPersistence))
        #expect(recorder.persistenceRetryCount == 1)
        #expect(recorder.routingResumeCount == 0)
        #expect(recorder.restartCount == 0)

        #expect(await dispatcher.perform(.resumeRouting))
        #expect(recorder.persistenceRetryCount == 1)
        #expect(recorder.routingResumeCount == 1)
        #expect(recorder.restartCount == 0)

        #expect(await dispatcher.perform(.restart))
        #expect(recorder.historyRetryCount == 1)
        #expect(recorder.restorationRetryCount == 1)
        #expect(recorder.restartCount == 1)
    }

    @Test func recoveryRenderingAlwaysContainsAtMostOneAction() throws {
        let startup = try #require(AppRootRecoveryRendering(
            presentation: AppRootPresentation(
                startupPhase: .recovery,
                hasPendingTerminalHistoryReconciliation: false,
                persistenceWarnings: [.recoveryStoreUnavailable]
            )
        ))
        #expect(startup.pageState?.actions.count == 1)
        #expect(startup.banner == nil)

        let shell = try #require(AppRootRecoveryRendering(
            presentation: AppRootPresentation(
                startupPhase: .shell,
                hasPendingTerminalHistoryReconciliation: true,
                persistenceWarnings: [.historyNotSaved]
            )
        ))
        #expect(shell.pageState == nil)
        #expect(shell.banner?.primaryAction.id == "recovery.history.retry")
    }

    @Test func onboardingShowsSeriousRecoveryButDoesNotDuplicateItsOwnSaveFailure() throws {
        let recoveredStore = try #require(AppRootRecoveryRendering(
            presentation: AppRootPresentation(
                startupPhase: .onboarding,
                hasPendingTerminalHistoryReconciliation: false,
                persistenceWarnings: [.corruptStoreRecovered(backupLocation: "/tmp/backup")]
            )
        ))
        #expect(recoveredStore.onboardingBanner(suppressing: nil)?.primaryAction.id ==
            "recovery.restart")

        let settingsFailure = try #require(AppRootRecoveryRendering(
            presentation: AppRootPresentation(
                startupPhase: .onboarding,
                hasPendingTerminalHistoryReconciliation: false,
                persistenceWarnings: [.settingsNotSaved]
            )
        ))
        #expect(settingsFailure.onboardingBanner(suppressing: .settingsNotSaved) == nil)
    }

    @Test func recoveryControllerPreventsDuplicateActionsAndReenablesRetryAfterFailure() async {
        let gate = SuspendedRootRecovery()
        let controller = AppRootRecoveryController(dispatcher: AppRootRecoveryDispatcher(
            retryPendingTerminalHistory: {
                await gate.retry()
            },
            retryRestoration: { true },
            retryPendingPersistence: { true },
            resumeRouting: { true },
            restart: { true }
        ))

        controller.perform(.retryHistory)
        await gate.waitUntilStarted()

        #expect(controller.isPerformingAction)
        controller.perform(.retryHistory)
        #expect(await gate.callCount == 1)

        await gate.finish(result: false)
        while controller.isPerformingAction {
            await Task.yield()
        }

        #expect(!controller.isPerformingAction)
        controller.perform(.retryHistory)
        while await gate.callCount < 2 {
            await Task.yield()
        }
        #expect(await gate.callCount == 2)
        await gate.finish(result: true)
    }

    @Test func recoveryRenderingExposesBusyStateToBannerAndRecoveryPage() throws {
        let shell = try #require(AppRootRecoveryRendering(
            presentation: AppRootPresentation(
                startupPhase: .shell,
                hasPendingTerminalHistoryReconciliation: true,
                persistenceWarnings: [.historyNotSaved]
            ),
            isPerformingAction: true
        ))
        let startup = try #require(AppRootRecoveryRendering(
            presentation: AppRootPresentation(
                startupPhase: .recovery,
                hasPendingTerminalHistoryReconciliation: false,
                persistenceWarnings: [.recoveryStoreUnavailable]
            ),
            isPerformingAction: true
        ))

        #expect(shell.banner?.isPerformingAction == true)
        #expect(shell.banner?.canPerformAction == false)
        #expect(startup.pageState?.isPerformingAction == true)
        #expect(startup.pageState?.canPerformActions == false)
    }
}

@Suite("App root system actions")
@MainActor
struct AppRootSystemActionsTests {
    @Test func cancellingCustomBrowserSelectionHasNoPersistenceSideEffect() async {
        let saver = RecordingRootCustomBrowserSaver()
        let actions = AppRootSystemActions(
            chooseCustomBrowserApplication: { nil },
            customBrowserSaver: saver,
            openDefaultAppsSettings: { true },
            openApplicationsFolder: { true },
            restart: { true }
        )

        #expect(await actions.addCustomBrowser() == .cancelled)
        #expect(saver.savedURLs.isEmpty)
    }

    @Test func nonApplicationSelectionFailsWithoutCallingTheCatalog() async {
        let saver = RecordingRootCustomBrowserSaver()
        let actions = AppRootSystemActions(
            chooseCustomBrowserApplication: { URL(fileURLWithPath: "/tmp/not-a-browser.txt") },
            customBrowserSaver: saver,
            openDefaultAppsSettings: { true },
            openApplicationsFolder: { true },
            restart: { true }
        )

        #expect(await actions.addCustomBrowser() == .failed)
        #expect(saver.savedURLs.isEmpty)
    }

    @Test func applicationSelectionIsValidatedAndSavedByTheBrowserCatalogBoundary() async {
        let saver = RecordingRootCustomBrowserSaver()
        let selectedURL = URL(fileURLWithPath: "/Applications/Fixture Browser.app")
        let actions = AppRootSystemActions(
            chooseCustomBrowserApplication: { selectedURL },
            customBrowserSaver: saver,
            openDefaultAppsSettings: { true },
            openApplicationsFolder: { true },
            restart: { true }
        )

        #expect(await actions.addCustomBrowser() == .added)
        #expect(saver.savedURLs == [selectedURL])
    }

    @Test func catalogRejectionIsReportedAsFailure() async {
        let saver = RecordingRootCustomBrowserSaver(shouldFail: true)
        let actions = AppRootSystemActions(
            chooseCustomBrowserApplication: {
                URL(fileURLWithPath: "/Applications/Rejected Browser.app")
            },
            customBrowserSaver: saver,
            openDefaultAppsSettings: { true },
            openApplicationsFolder: { true },
            restart: { true }
        )

        #expect(await actions.addCustomBrowser() == .failed)
        #expect(saver.savedURLs.count == 1)
    }
}

@MainActor
private final class RootRecoveryRecorder {
    var historyRetryCount = 0
    var restorationRetryCount = 0
    var persistenceRetryCount = 0
    var routingResumeCount = 0
    var restartCount = 0
}

@MainActor
private final class RecordingRootCustomBrowserSaver: AppRootCustomBrowserSaving {
    private let shouldFail: Bool
    private(set) var savedURLs: [URL] = []

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func saveCustomBrowser(at applicationURL: URL) throws -> BrowserDescriptor {
        savedURLs.append(applicationURL)
        if shouldFail { throw RootViewTestFailure.rejected }
        return BrowserDescriptor(
            id: BrowserID("com.example.fixture-browser"),
            bundleIdentifier: "com.example.fixture-browser",
            displayName: "Fixture Browser",
            applicationURL: applicationURL,
            securityScopedBookmark: nil,
            origin: .custom,
            availability: .available,
            selectorOrder: 0
        )
    }
}

@MainActor
private func makeRootComposition() -> ProductionAppComposition {
    ProductionAppComposition.makeForTesting(
        modelContainerFactory: { try ModelContainerFactory.make(inMemory: true) },
        recoveryStoreFactory: { RootPendingRequestStore() }
    )
}

private enum RootViewTestFailure: Error {
    case rejected
}

private actor RootPendingRequestStore: PendingRequestStore, PersistenceWarningSource {
    private var snapshot = PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])

    func load() async throws -> PendingRequestSnapshot {
        snapshot
    }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        self.snapshot = snapshot
    }

    func drainPersistenceWarnings() async -> [PersistenceWarning] {
        []
    }
}

private actor SuspendedRootRecovery {
    private(set) var callCount = 0
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var resultContinuations: [CheckedContinuation<Bool, Never>] = []

    func retry() async -> Bool {
        callCount += 1
        let waiting = startedContinuations
        startedContinuations.removeAll()
        waiting.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            resultContinuations.append(continuation)
        }
    }

    func waitUntilStarted() async {
        if callCount > 0 { return }
        await withCheckedContinuation { continuation in
            startedContinuations.append(continuation)
        }
    }

    func finish(result: Bool) {
        guard !resultContinuations.isEmpty else { return }
        resultContinuations.removeFirst().resume(returning: result)
    }
}
