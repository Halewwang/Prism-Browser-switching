import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("Onboarding presentation")
struct OnboardingViewPresentationTests {
    @Test func fourStepsExposeStableProgressAndReadableDestinations() {
        let presentations = OnboardingStep.allCases.map {
            makePresentation(step: $0)
        }

        #expect(presentations.map(\.progressText) == [
            "Step 1 of 4",
            "Step 2 of 4",
            "Step 3 of 4",
            "Step 4 of 4",
        ])
        #expect(presentations.map(\.accessibilityIdentifier) == [
            "onboarding.step.welcome",
            "onboarding.step.linkHandling",
            "onboarding.step.browsers",
            "onboarding.step.testLink",
        ])
        #expect(presentations.map(\.title) == [
            "Your links, in the right browser",
            "Let Prism handle web links",
            "Choose available browsers",
            "Try Prism with a test link",
        ])
    }

    @Test func linkHandlingReportsHTTPAndHTTPSIndependentlyWithoutColorOnlyMeaning() {
        let presentation = makePresentation(
            step: .linkHandling,
            httpHandlerIsActive: true,
            httpsHandlerIsActive: false
        )

        #expect(presentation.statusRows == [
            OnboardingStatusRowPresentation(
                id: "http",
                title: "HTTP links",
                statusText: "Prism is active",
                iconSystemName: "checkmark.circle.fill",
                accessibilityIdentifier: "onboarding.linkHandling.httpStatus"
            ),
            OnboardingStatusRowPresentation(
                id: "https",
                title: "HTTPS links",
                statusText: "Needs attention",
                iconSystemName: "exclamationmark.circle.fill",
                accessibilityIdentifier: "onboarding.linkHandling.httpsStatus"
            ),
        ])
        #expect(presentation.actions.map(\.id) == [
            .setAsDefault,
            .refreshHandlers,
            .finishLinkHandlingLater,
        ])
    }

    @Test func firstLinkHandlingPresentationKeepsUnqueriedHandlersUnknown() {
        let presentation = makePresentation(
            step: .linkHandling,
            handlerStatusIsKnown: false,
            isCheckingHandlers: true
        )

        #expect(presentation.statusRows.allSatisfy { $0.statusText == "Checking…" })
        #expect(presentation.activityText == "Checking HTTP and HTTPS handlers…")
        #expect(presentation.actions.allSatisfy { !$0.isEnabled })
        #expect(!presentation.visibleText.contains("Needs attention"))
    }

    @Test func preferredKeyboardFocusTracksTheFirstActionThatBecomesUsable() {
        let checking = makePresentation(
            step: .linkHandling,
            handlerStatusIsKnown: false,
            isCheckingHandlers: true
        )
        let handlerFailure = makePresentation(
            step: .linkHandling,
            alert: .defaultHandlerIncomplete
        )
        let testFailure = makePresentation(
            step: .testLink,
            alert: .testLinkFailed
        )
        let saveFailure = makePresentation(
            step: .testLink,
            alert: .settingsNotSaved,
            testLinkWasAccepted: true
        )

        #expect(checking.preferredFocusedActionID == nil)
        #expect(handlerFailure.preferredFocusedActionID == .setAsDefault)
        #expect(testFailure.preferredFocusedActionID == .retryTestLink)
        #expect(saveFailure.preferredFocusedActionID == .retryCompletionSave)
    }

    @Test func linkHandlingRecoveryOffersInjectedSystemSettingsRoute() {
        let presentation = makePresentation(
            step: .linkHandling,
            alert: .defaultHandlerIncomplete
        )

        #expect(presentation.alert?.title == "Prism is not handling every web link")
        #expect(presentation.actions.map(\.id) == [
            .setAsDefault,
            .refreshHandlers,
            .openDefaultAppsSettings,
            .finishLinkHandlingLater,
        ])
        #expect(presentation.actions.first { $0.id == .openDefaultAppsSettings }?.accessibilityIdentifier ==
            "onboarding.linkHandling.openSettings")
    }

    @Test func handlerRefreshExplainsProgressAndPreventsDuplicateRequests() {
        let presentation = makePresentation(
            step: .linkHandling,
            isRefreshingHandler: true
        )

        #expect(presentation.activityText == "Checking HTTP and HTTPS handlers…")
        #expect(presentation.actions.allSatisfy { !$0.isEnabled })
        #expect(presentation.statusRows.allSatisfy { $0.statusText == "Checking…" })
    }

    @Test func emptyBrowserStepKeepsAllThreeRecoveryPaths() {
        let presentation = makePresentation(step: .browsers)

        #expect(presentation.browserRows.isEmpty)
        #expect(presentation.actions.map(\.id) == [
            .rescanBrowsers,
            .addCustomBrowser,
            .openApplicationsFolder,
        ])
        #expect(presentation.actions.map(\.accessibilityIdentifier) == [
            "onboarding.browsers.rescan",
            "onboarding.browsers.addCustomBrowser",
            "onboarding.browsers.openApplicationsFolder",
        ])
    }

    @Test func browserScanFailureAndNoBrowserRemainDistinctReadableStates() {
        let failed = makePresentation(step: .browsers, alert: .browserScanFailed)
        let empty = makePresentation(step: .browsers, alert: .noUsableBrowser)

        #expect(failed.alert?.title == "Browsers could not be scanned")
        #expect(empty.alert?.title == "No usable browsers were found")
        #expect(failed.alert?.iconSystemName == "exclamationmark.triangle.fill")
        #expect(empty.alert?.iconSystemName == "safari.fill")
        #expect(failed.actions.map(\.id) == empty.actions.map(\.id))
    }

    @Test func usableBrowsersAreListedInsteadOfShowingEmptyRecoveryActions() {
        let presentation = makePresentation(
            step: .browsers,
            usableBrowsers: [
                browser(
                    id: "com.example.one",
                    name: "First Browser",
                    path: "/Applications/First Browser.app"
                ),
                browser(
                    id: "com.example.two",
                    name: "Second Browser",
                    path: "/Applications/Second Browser.app"
                ),
            ]
        )

        #expect(presentation.browserRows.map(\.name) == ["First Browser", "Second Browser"])
        #expect(presentation.browserRows.map(\.location) == [
            "/Applications/First Browser.app",
            "/Applications/Second Browser.app",
        ])
        #expect(presentation.browserRows.allSatisfy { $0.statusText == "Ready" })
        #expect(presentation.actions.isEmpty)
    }

    @Test func usableBrowserWithFailedSettingsSaveKeepsAWorkingRetryAction() {
        let presentation = makePresentation(
            step: .browsers,
            alert: .settingsNotSaved,
            usableBrowsers: [browser(
                id: "com.example.one",
                name: "First Browser",
                path: "/Applications/First Browser.app"
            )]
        )

        #expect(presentation.browserRows.map(\.name) == ["First Browser"])
        #expect(presentation.actions.map(\.id) == [.rescanBrowsers])
        #expect(presentation.actions.map(\.title) == ["Retry Saving Setup"])
        #expect(presentation.actions.first?.accessibilityIdentifier ==
            "onboarding.browsers.retrySave")
    }

    @Test func browserScanShowsProgressAndDisablesAllRecoveryActions() {
        let presentation = makePresentation(
            step: .browsers,
            isScanningBrowsers: true
        )

        #expect(presentation.activityText == "Looking for installed browsers…")
        #expect(presentation.actions.map(\.id) == [
            .rescanBrowsers,
            .addCustomBrowser,
            .openApplicationsFolder,
        ])
        #expect(presentation.actions.allSatisfy { !$0.isEnabled })
    }

    @Test func testLinkProgressNeverClaimsSuccessOrOffersAnImpossibleRetry() {
        let presentation = makePresentation(
            step: .testLink,
            alert: .testLinkFailed,
            isTestLinkInProgress: true
        )

        #expect(presentation.activityText == "Waiting for the browser to accept the test link…")
        #expect(presentation.actions.map(\.id) == [.finishTestLater])
        #expect(presentation.actions.first?.title == "Finish Later")
        #expect(!presentation.visibleText.contains { $0.localizedCaseInsensitiveContains("success") })
    }

    @Test func testLinkPreparationDisablesFinishLaterUntilTheRequestCanBeCancelled() {
        let preparing = makePresentation(
            step: .testLink,
            isTestLinkInProgress: true,
            isTestLinkPreparing: true
        )
        let cancellable = makePresentation(
            step: .testLink,
            isTestLinkInProgress: true,
            isTestLinkPreparing: false
        )

        #expect(preparing.actions.map(\.id) == [.finishTestLater])
        #expect(preparing.actions.first?.isEnabled == false)
        #expect(cancellable.actions.map(\.id) == [.finishTestLater])
        #expect(cancellable.actions.first?.isEnabled == true)
    }

    @Test func terminalTestFailureOffersRetryAndAnExplicitFinishLaterChoice() {
        let presentation = makePresentation(
            step: .testLink,
            alert: .testLinkFailed
        )

        #expect(presentation.alert?.title == "The test link did not finish")
        #expect(presentation.actions.map(\.id) == [.retryTestLink, .finishTestLater])
        #expect(presentation.actions.map(\.title) == ["Retry Test Link", "Finish Later"])
        #expect(presentation.actions.map(\.accessibilityIdentifier) == [
            "onboarding.testLink.retry",
            "onboarding.testLink.finishLater",
        ])
        #expect(!presentation.visibleText.contains { $0.localizedCaseInsensitiveContains("success") })
    }

    @Test func acceptedHandoffSaveFailureOffersCompletionSaveOnly() {
        let presentation = makePresentation(
            step: .testLink,
            alert: .settingsNotSaved,
            testLinkWasAccepted: true
        )

        #expect(presentation.actions.map(\.id) == [.retryCompletionSave])
        #expect(presentation.actions.map(\.title) == ["Retry Saving Setup"])
        #expect(presentation.actions.first?.accessibilityIdentifier ==
            "onboarding.testLink.retryCompletionSave")
        #expect(!presentation.actions.contains { $0.id == .startTestLink || $0.id == .retryTestLink })
    }

    @Test func idleTestStepStartsTheRealTestAndKeepsFinishLaterHonest() {
        let presentation = makePresentation(step: .testLink)

        #expect(presentation.actions.map(\.id) == [.startTestLink, .finishTestLater])
        #expect(presentation.actions.map(\.title) == ["Test Link", "Finish Later"])
        #expect(presentation.message.contains("selector"))
        #expect(presentation.message.contains("browser"))
    }

    @Test(arguments: OnboardingAlert.allCasesForPresentationTests)
    func everyAlertHasANonColorCueAndReadableRecoveryMessage(alert: OnboardingAlert) {
        let step: OnboardingStep = switch alert {
        case .defaultHandlerIncomplete, .defaultHandlerUnavailable:
            .linkHandling
        case .noUsableBrowser, .browserScanFailed, .customBrowserFailed:
            .browsers
        case .settingsNotSaved, .testLinkFailed, .testLinkCancellationFailed:
            .testLink
        }
        let presentation = makePresentation(step: step, alert: alert)

        #expect(!(presentation.alert?.iconSystemName.isEmpty ?? true))
        #expect(!(presentation.alert?.title.isEmpty ?? true))
        #expect(!(presentation.alert?.message.isEmpty ?? true))
        #expect(presentation.alert?.accessibilityIdentifier == "onboarding.alert")
    }
}

@Suite("Onboarding external actions")
@MainActor
struct OnboardingExternalActionTests {
    @Test func systemRoutesRemainInjectedAndDispatchOnlyTheirMatchingClosure() async {
        var received: [OnboardingExternalAction] = []
        let actions = OnboardingViewActions(
            addCustomBrowser: {
                received.append(.addCustomBrowser)
                return .added
            },
            openDefaultAppsSettings: { received.append(.openDefaultAppsSettings) },
            openApplicationsFolder: { received.append(.openApplicationsFolder) }
        )

        #expect(await actions.addCustomBrowser() == .added)
        actions.openSettings()
        actions.openApplications()

        #expect(received == OnboardingExternalAction.allCases)
    }

    @Test func cancelledAndFailedBrowserPickerResultsRemainDistinctFromAddition() async {
        let cancelled = OnboardingViewActions(
            addCustomBrowser: { .cancelled },
            openDefaultAppsSettings: {},
            openApplicationsFolder: {}
        )
        let failed = OnboardingViewActions(
            addCustomBrowser: { .failed },
            openDefaultAppsSettings: {},
            openApplicationsFolder: {}
        )

        #expect(await cancelled.addCustomBrowser() == .cancelled)
        #expect(await failed.addCustomBrowser() == .failed)
    }
}

private extension OnboardingAlert {
    static let allCasesForPresentationTests: [OnboardingAlert] = [
        .defaultHandlerIncomplete,
        .defaultHandlerUnavailable,
        .noUsableBrowser,
        .browserScanFailed,
        .customBrowserFailed,
        .settingsNotSaved,
        .testLinkFailed,
        .testLinkCancellationFailed,
    ]
}

private func makePresentation(
    step: OnboardingStep,
    alert: OnboardingAlert? = nil,
    httpHandlerIsActive: Bool = false,
    httpsHandlerIsActive: Bool = false,
    usableBrowsers: [BrowserDescriptor] = [],
    isTestLinkInProgress: Bool = false,
    isTestLinkPreparing: Bool = false,
    isRefreshingHandler: Bool = false,
    isScanningBrowsers: Bool = false,
    handlerStatusIsKnown: Bool = true,
    isCheckingHandlers: Bool = false,
    testLinkWasAccepted: Bool = false
) -> OnboardingViewPresentation {
    OnboardingViewPresentation(
        step: step,
        alert: alert,
        httpHandlerIsActive: httpHandlerIsActive,
        httpsHandlerIsActive: httpsHandlerIsActive,
        usableBrowsers: usableBrowsers,
        isTestLinkInProgress: isTestLinkInProgress,
        isTestLinkPreparing: isTestLinkPreparing,
        isRefreshingHandler: isRefreshingHandler,
        isScanningBrowsers: isScanningBrowsers,
        handlerStatusIsKnown: handlerStatusIsKnown,
        isCheckingHandlers: isCheckingHandlers,
        testLinkWasAccepted: testLinkWasAccepted
    )
}

private func browser(
    id: String,
    name: String,
    path: String
) -> BrowserDescriptor {
    BrowserDescriptor(
        id: BrowserID(id),
        bundleIdentifier: id,
        displayName: name,
        applicationURL: URL(fileURLWithPath: path),
        securityScopedBookmark: nil,
        origin: .system,
        availability: .available,
        selectorOrder: 0
    )
}
