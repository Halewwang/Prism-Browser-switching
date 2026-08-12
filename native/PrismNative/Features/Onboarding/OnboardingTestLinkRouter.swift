import Foundation

@MainActor
final class OnboardingTestLinkSession {
    let requestID: UUID

    private let observationID: UUID
    private weak var outcomes: LinkRoutingOutcomeCenter?
    private weak var coordinator: (any LinkRoutingCoordinating)?
    private var isObserving = true

    init(
        requestID: UUID,
        observationID: UUID,
        outcomes: LinkRoutingOutcomeCenter,
        coordinator: any LinkRoutingCoordinating
    ) {
        self.requestID = requestID
        self.observationID = observationID
        self.outcomes = outcomes
        self.coordinator = coordinator
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        outcomes?.removeObservation(id: observationID, requestID: requestID)
    }

    func cancel() async -> LinkRoutingCancellationResult {
        guard let coordinator else { return .notCancelled }
        let result = await coordinator.cancelForExplicitSelection(requestID: requestID)
        if result == .cancelled {
            stopObserving()
        }
        return result
    }

    isolated deinit {
        if isObserving {
            outcomes?.removeObservation(id: observationID, requestID: requestID)
        }
    }
}

@MainActor
final class OnboardingTestLinkRouter {
    typealias OutcomeHandler = @MainActor (LinkRoutingOutcome) async -> Bool

    private let intake: LinkIntakeService
    private let coordinator: any LinkRoutingCoordinating
    private let outcomes: LinkRoutingOutcomeCenter

    init(
        intake: LinkIntakeService,
        coordinator: any LinkRoutingCoordinating,
        outcomes: LinkRoutingOutcomeCenter
    ) {
        self.intake = intake
        self.coordinator = coordinator
        self.outcomes = outcomes
    }

    @discardableResult
    func start(
        url: URL,
        onPrepared: @MainActor (OnboardingTestLinkSession) -> Bool,
        onOutcome: @escaping OutcomeHandler
    ) async -> OnboardingTestLinkSession? {
        guard let requestID = await intake.captureForExplicitSelection(
            url: url,
            senderPID: nil
        ) else {
            return nil
        }

        let observationID = outcomes.observe(requestID: requestID, handler: onOutcome)
        let session = OnboardingTestLinkSession(
            requestID: requestID,
            observationID: observationID,
            outcomes: outcomes,
            coordinator: coordinator
        )
        guard onPrepared(session) else {
            _ = await session.cancel()
            return nil
        }
        guard await coordinator.presentForExplicitSelection(requestID: requestID) else {
            _ = await session.cancel()
            return nil
        }
        return session
    }
}
