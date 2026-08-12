import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("Onboarding view interaction")
@MainActor
struct OnboardingViewInteractionTests {
    @Test func cancellingCustomBrowserPickerDoesNotScanOrChangeTheCurrentState() async {
        let fixture = OnboardingViewInteractionFixture(customBrowserResult: .cancelled)
        await fixture.prepareBrowserStep()

        await fixture.interactions.addCustomBrowser()

        #expect(fixture.catalog.scanCount == 0)
        #expect(fixture.model.step == .browsers)
        #expect(fixture.model.alert == nil)
    }

    @Test func failedCustomBrowserSelectionShowsRecoveryWithoutScanning() async {
        let fixture = OnboardingViewInteractionFixture(customBrowserResult: .failed)
        await fixture.prepareBrowserStep()

        await fixture.interactions.addCustomBrowser()

        #expect(fixture.catalog.scanCount == 0)
        #expect(fixture.model.step == .browsers)
        #expect(fixture.model.alert == .customBrowserFailed)
    }

    @Test func addedCustomBrowserScansExactlyOnce() async {
        let fixture = OnboardingViewInteractionFixture(customBrowserResult: .added)
        await fixture.prepareBrowserStep()

        await fixture.interactions.addCustomBrowser()

        #expect(fixture.catalog.scanCount == 1)
        #expect(fixture.model.step == .testLink)
    }

    @Test func viewReadsTheObservableModelAfterAnAsyncTransition() async {
        let fixture = OnboardingViewInteractionFixture(customBrowserResult: .cancelled)

        let view = OnboardingView(
            model: fixture.model,
            actions: fixture.actions
        )

        #expect(view.presentation.step == .welcome)

        await fixture.model.advanceFromWelcome()

        #expect(view.presentation.step == .linkHandling)
        #expect(view.presentation.statusRows.map(\.statusText) == [
            "Needs attention",
            "Needs attention",
        ])
    }
}

@MainActor
private struct OnboardingViewInteractionFixture {
    let model: OnboardingViewModel
    let catalog = CountingOnboardingBrowserCatalog()
    let actions: OnboardingViewActions
    let interactions: OnboardingViewInteractions

    init(customBrowserResult: OnboardingCustomBrowserResult) {
        let environment = AppEnvironment(
            route: .history,
            unmatchedBehavior: .alwaysAsk,
            updateChecker: DisabledUpdateChecker(),
            ruleRepository: InMemoryRuleRepository(),
            historyRepository: InMemoryHistoryRepository(),
            browserPreferenceRepository: InMemoryBrowserPreferenceRepository(),
            settingsRepository: InMemorySettingsRepository()
        )
        let queue = LinkRequestQueue(store: InMemoryPendingRequestStore())
        let outcomes = LinkRoutingOutcomeCenter()
        let coordinator = ViewInteractionCoordinator()
        let intake = LinkIntakeService(
            queue: queue,
            bootstrap: BootstrapLinkBuffer(),
            sourceAttributor: ViewInteractionSourceAttributor(),
            lastActivatedSource: { nil },
            coordinator: coordinator
        )
        model = OnboardingViewModel(
            environment: environment,
            defaultBrowserService: DefaultBrowserService(
                client: ViewInteractionDefaultHandlerClient(),
                applicationURL: URL(fileURLWithPath: "/Applications/Prism.app"),
                bundleIdentifier: "com.prism.app"
            ),
            browserCatalog: catalog,
            testLinkRouter: OnboardingTestLinkRouter(
                intake: intake,
                coordinator: coordinator,
                outcomes: outcomes
            ),
            openMainWindow: { _ in },
            resumeRouting: {}
        )
        actions = OnboardingViewActions(
            addCustomBrowser: { customBrowserResult },
            openDefaultAppsSettings: {},
            openApplicationsFolder: {}
        )
        interactions = OnboardingViewInteractions(model: model, actions: actions)
    }

    func prepareBrowserStep() async {
        await model.advanceFromWelcome()
        model.finishLater()
    }
}

@MainActor
private final class CountingOnboardingBrowserCatalog: BrowserCataloging {
    private(set) var scanCount = 0

    func scan() async throws -> [BrowserDescriptor] {
        scanCount += 1
        return [BrowserDescriptor(
            id: "com.example.browser",
            bundleIdentifier: "com.example.browser",
            displayName: "Example Browser",
            applicationURL: URL(fileURLWithPath: "/Applications/Example Browser.app"),
            securityScopedBookmark: nil,
            origin: .system,
            availability: .available,
            selectorOrder: 0
        )]
    }
}

@MainActor
private final class ViewInteractionDefaultHandlerClient: DefaultHandlerClient {
    func handlerBundleIdentifier(forScheme _: String) -> String? { "com.example.other" }
    func setDefault(applicationURL _: URL, forScheme _: String) async throws {}
}

@MainActor
private final class ViewInteractionCoordinator: LinkRoutingCoordinating {
    func processNext(
        while _: @escaping @MainActor () -> Bool
    ) async -> LinkRoutingPassDisposition { .drained }
    func presentForExplicitSelection(requestID _: UUID) async -> Bool { false }
    func select(browserID _: BrowserID, for _: UUID) async {}
    func retry(browserID _: BrowserID, for _: UUID) async {}
    func markUncertainAttemptCompleted(requestID _: UUID) async {}
    func cancel(requestID _: UUID) async {}
}

private struct ViewInteractionSourceAttributor: SourceAttributing {
    func resolve(senderPID _: Int32?, lastActivated _: SourceApplication?) -> SourceApplication {
        .unknown
    }
}
