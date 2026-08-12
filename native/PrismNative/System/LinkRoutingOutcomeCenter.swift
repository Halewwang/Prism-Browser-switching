import Foundation

struct LinkRoutingOutcome: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case handoffAccepted
        case handoffFailed
        case cancelled
        case completedWithoutConfirmedHandoff
        case outcomeUnknown
        case unavailable
        case storageUnavailable

        var isTerminal: Bool {
            switch self {
            case .handoffAccepted, .cancelled, .completedWithoutConfirmedHandoff:
                true
            case .handoffFailed, .outcomeUnknown, .unavailable, .storageUnavailable:
                false
            }
        }
    }

    let requestID: UUID
    let kind: Kind
}

@MainActor
protocol LinkRoutingOutcomeReporting: AnyObject {
    func report(_ outcome: LinkRoutingOutcome) async
}

@MainActor
final class LinkRoutingOutcomeCenter: LinkRoutingOutcomeReporting {
    typealias Observer = @MainActor (LinkRoutingOutcome) async -> Bool

    private final class Observation {
        let id: UUID
        let requestID: UUID
        let handler: Observer

        init(id: UUID, requestID: UUID, handler: @escaping Observer) {
            self.id = id
            self.requestID = requestID
            self.handler = handler
        }
    }

    private var observations: [UUID: Observation] = [:]
    private var observationsByID: [UUID: Observation] = [:]

    @discardableResult
    func observe(requestID: UUID, handler: @escaping Observer) -> UUID {
        let observation = Observation(id: UUID(), requestID: requestID, handler: handler)
        if let replaced = observations[requestID] {
            observationsByID[replaced.id] = nil
        }
        observations[requestID] = observation
        observationsByID[observation.id] = observation
        return observation.id
    }

    func removeObservation(id: UUID, requestID: UUID) {
        guard let observation = observationsByID[id], observation.requestID == requestID else {
            return
        }
        observationsByID[id] = nil
        if observations[requestID] === observation {
            observations[requestID] = nil
        }
    }

    func report(_ outcome: LinkRoutingOutcome) async {
        guard let observation = observations.removeValue(forKey: outcome.requestID) else {
            return
        }
        let keepObserving = await observation.handler(outcome)
        guard observationsByID[observation.id] === observation else { return }
        if keepObserving, !outcome.kind.isTerminal, observations[outcome.requestID] == nil {
            observations[outcome.requestID] = observation
        } else {
            observationsByID[observation.id] = nil
        }
    }
}
