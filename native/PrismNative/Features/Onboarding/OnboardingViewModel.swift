import Foundation
import Observation
import PrismCore

@MainActor
@Observable
final class OnboardingViewModel {
    private let environment: AppEnvironment
    private let defaultBrowserService: DefaultBrowserService
    private let browserCatalog: any BrowserCataloging
    private let testLinkRouter: OnboardingTestLinkRouter
    private let openMainWindow: @MainActor (AppRoute) -> Void
    private let resumeRouting: @MainActor () async -> Void
    private var testLinkSession: OnboardingTestLinkSession?
    private var testLinkGeneration: UUID?
    private var finishLaterCancellationRequestID: UUID?

    private(set) var step: OnboardingStep = .welcome
    private(set) var alert: OnboardingAlert?
    private(set) var httpHandlerIsActive = false
    private(set) var httpsHandlerIsActive = false
    private(set) var handlerStatusIsKnown = false
    private(set) var isCheckingHandlers = false
    private(set) var usableBrowsers: [BrowserDescriptor] = []
    private(set) var testLinkWasAccepted = false
    private(set) var completionSaveIsPending = false

    var isTestLinkInProgress: Bool {
        testLinkGeneration != nil || testLinkSession != nil
    }

    var isTestLinkPreparing: Bool {
        testLinkGeneration != nil && testLinkSession == nil
    }

    init(
        environment: AppEnvironment,
        defaultBrowserService: DefaultBrowserService,
        browserCatalog: any BrowserCataloging,
        testLinkRouter: OnboardingTestLinkRouter,
        openMainWindow: @escaping @MainActor (AppRoute) -> Void,
        resumeRouting: @escaping @MainActor () async -> Void
    ) {
        self.environment = environment
        self.defaultBrowserService = defaultBrowserService
        self.browserCatalog = browserCatalog
        self.testLinkRouter = testLinkRouter
        self.openMainWindow = openMainWindow
        self.resumeRouting = resumeRouting
    }

    func advanceFromWelcome() async {
        guard step == .welcome, !isCheckingHandlers else { return }
        alert = nil
        isCheckingHandlers = true
        step = .linkHandling
        defer { isCheckingHandlers = false }
        await queryCurrentHandler()
    }

    func advanceFromLinkHandling() async {
        guard step == .linkHandling, !isCheckingHandlers else { return }
        isCheckingHandlers = true
        defer { isCheckingHandlers = false }
        await queryCurrentHandler()
    }

    func setPrismAsDefault() async {
        guard step == .linkHandling, !isCheckingHandlers else { return }
        isCheckingHandlers = true
        defer { isCheckingHandlers = false }
        do {
            _ = try await defaultBrowserService.setAsDefaultAfterUserConfirmation()
        } catch {
            // The service can fail after registering only one scheme. Always
            // query the real handler state below instead of trusting the request.
        }
        await queryCurrentHandler()
    }

    func advanceFromBrowserScan() async {
        guard step == .browsers else { return }
        do {
            let scanned = try await browserCatalog.scan()
            usableBrowsers = scanned.filter { $0.availability == .available }
            guard !usableBrowsers.isEmpty else {
                alert = .noUsableBrowser
                return
            }
            guard environment.mutateSettings({ $0.unmatchedBehavior = .alwaysAsk }) else {
                alert = .settingsNotSaved
                return
            }
            alert = nil
            step = .testLink
        } catch {
            usableBrowsers = []
            alert = .browserScanFailed
        }
    }

    func reportCustomBrowserFailure() {
        guard step == .browsers else { return }
        alert = .customBrowserFailed
    }

    func beginTestLink() async {
        guard step == .testLink,
              testLinkGeneration == nil,
              testLinkSession == nil,
              !completionSaveIsPending
        else {
            return
        }
        let generation = UUID()
        testLinkGeneration = generation
        alert = nil

        let session = await testLinkRouter.start(
            url: URL(string: "https://example.com/prism-onboarding-test")!,
            onPrepared: { [weak self] session in
                guard let self,
                      self.testLinkGeneration == generation,
                      !self.environment.settings.onboardingCompleted
                else {
                    return false
                }
                self.testLinkSession = session
                return true
            }
        ) { [weak self] outcome in
            guard let self else { return false }
            return await self.receiveTestLinkOutcome(outcome)
        }

        guard testLinkGeneration == generation,
              !environment.settings.onboardingCompleted
        else {
            if let session {
                _ = await session.cancel()
            }
            return
        }
        testLinkGeneration = nil
        guard let session else {
            testLinkSession = nil
            alert = .testLinkFailed
            return
        }
        if testLinkSession?.requestID != session.requestID {
            testLinkSession = session
        }
    }

    func finishLater() {
        guard step == .linkHandling, !isCheckingHandlers else { return }
        alert = nil
        step = .browsers
    }

    func finishTestLater() async {
        guard step == .testLink, testLinkGeneration == nil else { return }
        if completionSaveIsPending {
            await retryCompletionSave()
            return
        }
        if let session = testLinkSession {
            finishLaterCancellationRequestID = session.requestID
            let cancellationResult = await session.cancel()
            finishLaterCancellationRequestID = nil
            guard cancellationResult == .cancelled else {
                alert = .testLinkCancellationFailed
                return
            }
            testLinkSession = nil
        }
        completionSaveIsPending = true
        await completeOnboarding()
    }

    func retryCompletionSave() async {
        guard step == .testLink,
              completionSaveIsPending,
              testLinkGeneration == nil,
              testLinkSession == nil
        else { return }
        await completeOnboarding()
    }

    private func queryCurrentHandler() async {
        do {
            let state = try await defaultBrowserService.status()
            updateHandlerState(state)
            handlerStatusIsKnown = true
            if state == .active {
                alert = nil
                step = .browsers
            } else {
                alert = .defaultHandlerIncomplete
            }
        } catch {
            handlerStatusIsKnown = false
            alert = .defaultHandlerUnavailable
        }
    }

    private func updateHandlerState(_ state: DefaultHandlerState) {
        switch state {
        case .active:
            httpHandlerIsActive = true
            httpsHandlerIsActive = true
        case let .inactive(http, https):
            httpHandlerIsActive = http
            httpsHandlerIsActive = https
        }
    }

    private func receiveTestLinkOutcome(_ outcome: LinkRoutingOutcome) async -> Bool {
        guard testLinkSession?.requestID == outcome.requestID else { return false }

        switch outcome.kind {
        case .handoffAccepted:
            testLinkGeneration = nil
            testLinkSession = nil
            testLinkWasAccepted = true
            completionSaveIsPending = true
            await completeOnboarding()
            return false
        case .cancelled where finishLaterCancellationRequestID == outcome.requestID:
            return false
        case .cancelled, .completedWithoutConfirmedHandoff:
            testLinkGeneration = nil
            testLinkSession = nil
            alert = .testLinkFailed
            return false
        case .handoffFailed, .outcomeUnknown, .unavailable, .storageUnavailable:
            alert = .testLinkFailed
            return true
        }
    }

    @discardableResult
    private func completeOnboarding() async -> Bool {
        guard environment.mutateSettings({ $0.onboardingCompleted = true }) else {
            alert = .settingsNotSaved
            return false
        }
        alert = nil
        testLinkWasAccepted = false
        completionSaveIsPending = false
        openMainWindow(.history)
        await resumeRouting()
        return true
    }
}
