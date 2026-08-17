#if DEBUG
import AppKit
import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Test func UItestConfigurationIsDisabledWithoutTheExplicitSafetyFlag() {
    #expect(DebugUITestConfiguration.parse(arguments: ["Prism"]) == .disabled)
}

@Test func plainUItestModeUsesTheSafeApplicationFixture() {
    let mode = DebugUITestConfiguration.parse(arguments: ["Prism", "--ui-testing"])

    #expect(mode == .application)
    #expect(mode.isUITesting)
    #expect(!mode.mayInstallSystemStatusItem)
    #expect(!mode.mayUseSystemServices)
}

@Test func validSelectorModeRequiresAnExplicitVariantAndAppearance() {
    let captureURL = URL(fileURLWithPath: "/tmp/prism-selector-contract.png")
    let mode = DebugUITestConfiguration.parse(arguments: [
        "Prism",
        "--ui-testing",
        "--selector-harness", "five",
        "--selector-appearance", "dark",
        "--selector-capture-path", captureURL.path,
    ])

    #expect(mode == .selector(
        variant: .five,
        appearance: .dark,
        captureURL: captureURL
    ))
    #expect(mode.isUITesting)
    #expect(!mode.mayInstallSystemStatusItem)
    #expect(!mode.mayUseSystemServices)
}

@Test(arguments: [
    ["Prism", "--ui-testing", "--selector-harness"],
    ["Prism", "--ui-testing", "--selector-harness", "unknown", "--selector-appearance", "light"],
    ["Prism", "--ui-testing", "--selector-harness", "three"],
    ["Prism", "--ui-testing", "--selector-harness", "three", "--selector-appearance", "unknown"],
    ["Prism", "--ui-testing", "--selector-harness", "three", "--selector-appearance", "light", "--selector-capture-path", "/Users/shared/not-allowed.png"],
])
func malformedSelectorArgumentsFailClosed(arguments: [String]) {
    let mode = DebugUITestConfiguration.parse(arguments: arguments)

    #expect(mode == .malformedSelector)
    #expect(mode.isUITesting)
    #expect(mode.blocksNormalLaunch)
    #expect(!mode.mayInstallSystemStatusItem)
    #expect(!mode.mayUseSystemServices)
}

@Test func productionModeIsTheOnlyModeAllowedToInstallARealStatusItemOrUseSystemServices() {
    #expect(DebugUITestMode.disabled.mayInstallSystemStatusItem)
    #expect(DebugUITestMode.disabled.mayUseSystemServices)
    #expect(!DebugUITestMode.application.mayInstallSystemStatusItem)
    #expect(!DebugUITestMode.application.mayUseSystemServices)
    #expect(!DebugUITestMode.malformedSelector.mayInstallSystemStatusItem)
    #expect(!DebugUITestMode.malformedSelector.mayUseSystemServices)
}

@Test @MainActor func debugApplicationFixtureRequestsARegularForegroundApplicationWithAllWindows() {
    let activator = DebugAppFixtureApplicationActivatorSpy()

    DebugAppFixtureActivationAnchor.requestForeground(using: activator)

    #expect(activator.receivedOptions == [[.activateAllWindows, .activateIgnoringOtherApps]])
}

@Test func debugApplicationFixtureHonorsTheExplicitLightAndDarkAppearanceArguments() {
    #expect(DebugApplicationFixtureAppearance(arguments: [
        "Prism", "-AppleInterfaceStyle", "Light",
    ]) == .light)
    #expect(DebugApplicationFixtureAppearance(arguments: [
        "Prism", "-AppleInterfaceStyle", "Dark",
    ]) == .dark)
    #expect(DebugApplicationFixtureAppearance(arguments: [
        "Prism", "-AppleInterfaceStyle", "Unknown",
    ]) == nil)
    #expect(DebugApplicationFixtureAppearance.current(
        arguments: ["Prism"],
        interfaceStylePreference: "Light"
    ) == .light)
}

@Test @MainActor func debugApplicationFixtureUsesOnlyRecordingServices() async throws {
    let fixture = DebugAppFixture.make(bootstrapBuffer: BootstrapLinkBuffer())

    await fixture.composition.finishLaunchingOnce()
    #expect(fixture.composition.environment.startupPhase == .onboarding)
    #expect(fixture.recorder.fixtureActivationObserverRegistrationCount == 1)

    #expect(try await fixture.composition.defaultBrowserService.status()
        == .inactive(http: false, https: false))
    #expect(try await fixture.composition.defaultBrowserService.setAsDefaultAfterUserConfirmation()
        == .active)
    let browsers = try await fixture.composition.browserCatalog.scan()
    #expect(browsers.map(\.bundleIdentifier) == ["invalid.prism.fixture.browser"])
    #expect(fixture.recorder.defaultHandlerReadCount == 4)
    #expect(fixture.recorder.defaultHandlerWriteCount == 2)
    #expect(fixture.recorder.browserScanCount == 1)

    var outcomes: [LinkRoutingOutcome] = []
    let session = await fixture.composition.onboardingTestLinkRouter.start(
        url: URL(string: "https://fixture.invalid/test")!,
        onPrepared: { _ in true },
        onOutcome: { outcome in
            outcomes.append(outcome)
            return false
        }
    )
    let requestID = try #require(session?.requestID)
    await fixture.composition.linkRoutingCoordinator.select(
        browserID: BrowserID("invalid.prism.fixture.browser"),
        for: requestID
    )

    #expect(fixture.recorder.browserHandoffCount == 1)
    #expect(outcomes == [LinkRoutingOutcome(requestID: requestID, kind: .handoffAccepted)])
}

@Test @MainActor func onboardingRecoveryFixtureUsesARealOnboardingBannerWithoutSystemServices() async {
    let fixture = DebugAppFixture.make(
        bootstrapBuffer: BootstrapLinkBuffer(),
        variant: .onboardingRecovery
    )

    await fixture.composition.finishLaunchingOnce()

    #expect(fixture.composition.environment.startupPhase == .onboarding)
    let presentation = AppRootPresentation(
        startupPhase: fixture.composition.environment.startupPhase,
        hasPendingTerminalHistoryReconciliation: false,
        persistenceWarnings: fixture.composition.environment.persistenceWarnings
    )
    #expect(AppRootRecoveryRendering(presentation: presentation)?.banner != nil)
    #expect(fixture.recorder.defaultHandlerWriteCount == 0)
    #expect(fixture.recorder.browserHandoffCount == 0)
}

@Test @MainActor func historyFixturesUseOnlyMemoryAndExposeSafeContentOrTheRequestedFailureState() async throws {
    let content = DebugAppFixture.make(
        bootstrapBuffer: BootstrapLinkBuffer(),
        variant: .history
    )
    await content.composition.finishLaunchingOnce()
    #expect(content.composition.environment.startupPhase == .shell)
    #expect(try await content.composition.environment.historyService.loadRecent(settings: .defaults).count == 2)
    #expect(content.recorder.browserHandoffCount == 0)

    let noURL = DebugAppFixture.make(
        bootstrapBuffer: BootstrapLinkBuffer(),
        variant: .historyNoURL
    )
    await noURL.composition.finishLaunchingOnce()
    let noURLEntries = try await noURL.composition.environment.historyService.loadRecent(settings: .defaults)
    #expect(noURLEntries.count == 1)
    #expect(noURLEntries.first?.sanitizedURL == nil)
    #expect(noURL.recorder.browserHandoffCount == 0)

    let actions = DebugAppFixture.make(
        bootstrapBuffer: BootstrapLinkBuffer(),
        variant: .historyActions
    )
    await actions.composition.finishLaunchingOnce()
    let activeRequestIDs = Set((await actions.composition.recoveryQueue.snapshot()).map(\.id))
    #expect(activeRequestIDs == [UUID(uuidString: "00000000-0000-0000-0000-000000000204")!])
    #expect(!(await actions.composition.linkRoutingCoordinator.canDeleteHistoryEntry(
        requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!
    )))
    #expect(actions.recorder.browserHandoffCount == 0)

    let failed = DebugAppFixture.make(
        bootstrapBuffer: BootstrapLinkBuffer(),
        variant: .historyLoadFailure
    )
    await failed.composition.finishLaunchingOnce()
    await #expect(throws: Error.self) {
        try await failed.composition.environment.historyService.loadRecent(settings: .defaults)
    }
    #expect(failed.recorder.browserHandoffCount == 0)
}

@Test @MainActor func debugStatusHostRecordsInstallationWithoutTouchingSystemStatusBar() {
    let recorder = DebugUITestEffectRecorder()
    let host = DebugNoopStatusItemHost(recorder: recorder)
    let menu = NSMenu()

    host.install(menu: menu)
    host.setVisible(true)
    host.setVisible(false)

    #expect(recorder.statusItemInstallCount == 1)
    #expect(recorder.statusItemVisibilityValues == [true, false])
}

@Test @MainActor func appDelegateUsesTheInjectedNoopStatusHostDuringApplicationUItests() async {
    let recorder = DebugUITestEffectRecorder()
    let fixture = DebugAppFixture.make(bootstrapBuffer: BootstrapLinkBuffer())
    let delegate = AppDelegate(
        composition: fixture.composition,
        copyCurrentSenderPID: { nil },
        makeStatusItemController: { composition in
            StatusItemController(
                host: DebugNoopStatusItemHost(recorder: recorder),
                mainWindowOpening: composition.mainWindowOpening,
                environment: composition.environment,
                updateChecker: composition.environment.updateChecker,
                terminate: {}
            )
        }
    )

    delegate.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification)
    )
    while fixture.composition.finishLaunchCount == 0 {
        await Task.yield()
    }

    #expect(delegate.retainedStatusItemController != nil)
    #expect(recorder.statusItemInstallCount == 1)
}

@MainActor
private final class DebugAppFixtureApplicationActivatorSpy: DebugAppFixtureApplicationActivating {
    private(set) var receivedOptions: [NSApplication.ActivationOptions] = []

    func activate(options: NSApplication.ActivationOptions) {
        receivedOptions.append(options)
    }
}
#endif
