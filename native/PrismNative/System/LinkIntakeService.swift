import Foundation
import PrismCore

struct BufferedLinkCapture: Equatable, Sendable {
    let id: UUID
    let sequence: UInt64
    let url: URL
    let senderPID: Int32?
    let receivedAt: Date
}

struct LinkCaptureDiagnostic: Equatable, Sendable {
    let timestamp: Date
    let sourceDisplayName: String
    let sourceBundleIdentifier: String?
    let senderPIDPresent: Bool
    let confidence: SourceConfidence
}

private enum LinkIntakeError: Error {
    case duplicateRequestID(UUID)
}

@MainActor
final class BootstrapLinkBuffer {
    private var captures: [BufferedLinkCapture] = []
    private var nextSequence: UInt64 = 0
    private let makeID: @MainActor () -> UUID
    private let now: @MainActor () -> Date

    init(
        makeID: @escaping @MainActor () -> UUID = UUID.init,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.makeID = makeID
        self.now = now
    }

    @discardableResult
    func capture(_ url: URL, senderPID: Int32?) -> Bool {
        guard Self.accepts(url) else { return false }
        let increment = nextSequence.addingReportingOverflow(1)
        guard !increment.overflow else { return false }

        captures.append(BufferedLinkCapture(
            id: makeID(),
            sequence: nextSequence,
            url: url,
            senderPID: senderPID,
            receivedAt: now()
        ))
        nextSequence = increment.partialValue
        return true
    }

    func snapshot() -> [BufferedLinkCapture] {
        captures
    }

    func first() -> BufferedLinkCapture? {
        captures.first
    }

    @discardableResult
    func removeFirst(ifSequenceMatches sequence: UInt64) -> Bool {
        guard captures.first?.sequence == sequence else { return false }
        captures.removeFirst()
        return true
    }

    static func accepts(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

@MainActor
final class LinkIntakeService {
    private let queue: LinkRequestQueue
    private let bootstrap: BootstrapLinkBuffer
    private let sourceAttributor: any SourceAttributing
    private let lastActivatedSource: @MainActor () -> SourceApplication?
    private let diagnosticRecorder: (@MainActor (LinkCaptureDiagnostic) -> Void)?
    private weak var coordinator: (any LinkRoutingCoordinating)?
    private weak var warningPresenter: (any PersistenceWarningPresenting)?
    private var restorationFinished = false
    private var routingEnabled = false
    private var persistencePaused = false
    private var drainTask: Task<Void, Never>?
    private(set) var workerStartCount = 0

    init(
        queue: LinkRequestQueue,
        bootstrap: BootstrapLinkBuffer,
        sourceAttributor: any SourceAttributing,
        lastActivatedSource: @escaping @MainActor () -> SourceApplication?,
        coordinator: (any LinkRoutingCoordinating)? = nil,
        warningPresenter: (any PersistenceWarningPresenting)? = nil,
        diagnosticRecorder: (@MainActor (LinkCaptureDiagnostic) -> Void)? = nil
    ) {
        self.queue = queue
        self.bootstrap = bootstrap
        self.sourceAttributor = sourceAttributor
        self.lastActivatedSource = lastActivatedSource
        self.coordinator = coordinator
        self.warningPresenter = warningPresenter
        self.diagnosticRecorder = diagnosticRecorder
    }

    @discardableResult
    func capture(url: URL, senderPID: Int32?) -> Bool {
        let accepted = bootstrap.capture(url, senderPID: senderPID)
        if accepted, restorationFinished, !persistencePaused {
            startDrainWorkerIfNeeded(routeAfterDraining: routingEnabled)
        }
        return accepted
    }

    func finishRestorationAndStartDraining(routeAfterDraining: Bool = true) {
        guard !restorationFinished else { return }
        restorationFinished = true
        routingEnabled = routeAfterDraining
        startDrainWorkerIfNeeded(routeAfterDraining: routeAfterDraining)
    }

    func resumeRoutingAfterRecoveryUserAction() async {
        guard restorationFinished,
              !routingEnabled,
              !persistencePaused,
              drainTask == nil,
              bootstrap.first() == nil
        else {
            return
        }
        routingEnabled = true
        await coordinator?.processNext()
    }

    func retryPendingPersistenceAfterUserAction() {
        guard restorationFinished, bootstrap.first() != nil else { return }
        persistencePaused = false
        routingEnabled = false
        startDrainWorkerIfNeeded(routeAfterDraining: false)
    }

    func drainForTesting() async throws {
        while let drainTask {
            await drainTask.value
        }
        try await drainBufferedLinks()
        await coordinator?.processNext()
    }

    func waitForDrainForTesting() async {
        while let drainTask {
            await drainTask.value
        }
    }

    private func startDrainWorkerIfNeeded(routeAfterDraining: Bool) {
        guard drainTask == nil else { return }
        workerStartCount += 1
        drainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var failed = false
            do {
                try await drainBufferedLinks()
                if routeAfterDraining, routingEnabled {
                    await coordinator?.processNext()
                }
            } catch {
                failed = true
                routingEnabled = false
                persistencePaused = true
                warningPresenter?.present(.recoveryStoreUnavailable)
            }
            drainTask = nil
            if !failed, restorationFinished, bootstrap.first() != nil {
                startDrainWorkerIfNeeded(
                    routeAfterDraining: routeAfterDraining && routingEnabled
                )
            }
        }
    }

    private func drainBufferedLinks() async throws {
        while let capture = bootstrap.first() {
            let source = sourceAttributor.resolve(
                senderPID: capture.senderPID,
                lastActivated: lastActivatedSource()
            )
            let request = LinkRequest(
                id: capture.id,
                url: capture.url,
                receivedAt: capture.receivedAt,
                source: source
            )
            guard try await queue.enqueue(request) else {
                throw LinkIntakeError.duplicateRequestID(request.id)
            }
            guard bootstrap.removeFirst(ifSequenceMatches: capture.sequence) else {
                continue
            }
            diagnosticRecorder?(LinkCaptureDiagnostic(
                timestamp: capture.receivedAt,
                sourceDisplayName: source.displayName,
                sourceBundleIdentifier: source.bundleIdentifier,
                senderPIDPresent: capture.senderPID != nil,
                confidence: source.confidence
            ))
        }
    }
}
