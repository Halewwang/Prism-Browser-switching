import Foundation
import Testing
@testable import PrismNative

@Test @MainActor
func removingAnObservationWhileItsHandlerIsSuspendedPreventsReinsertion() async {
    let center = LinkRoutingOutcomeCenter()
    let requestID = UUID()
    let gate = SuspendedOutcomeHandlerGate()
    var received: [LinkRoutingOutcome.Kind] = []
    let observationID = center.observe(requestID: requestID) { outcome in
        received.append(outcome.kind)
        if received.count == 1 {
            await gate.suspendHandler()
        }
        return true
    }

    let firstReport = Task { @MainActor in
        await center.report(LinkRoutingOutcome(
            requestID: requestID,
            kind: .handoffFailed
        ))
    }
    await gate.waitUntilHandlerIsSuspended()

    center.removeObservation(id: observationID, requestID: requestID)
    await gate.releaseHandler()
    await firstReport.value
    await center.report(LinkRoutingOutcome(
        requestID: requestID,
        kind: .storageUnavailable
    ))

    #expect(received == [.handoffFailed])
}

private actor SuspendedOutcomeHandlerGate {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var suspensionObservers: [CheckedContinuation<Void, Never>] = []

    func suspendHandler() async {
        let observers = suspensionObservers
        suspensionObservers.removeAll()
        observers.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilHandlerIsSuspended() async {
        if releaseContinuation != nil { return }
        await withCheckedContinuation { continuation in
            suspensionObservers.append(continuation)
        }
    }

    func releaseHandler() {
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}
