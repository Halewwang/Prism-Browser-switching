import Foundation
import PrismCore

struct BufferedLinkCapture: Equatable, Sendable {
    let id: UUID
    let sequence: UInt64
    let url: URL
    let senderPID: Int32?
    let receivedAt: Date
    let reopenedFromHistoryEntryID: UUID?
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
        captureRequest(url, senderPID: senderPID) != nil
    }

    @discardableResult
    func captureRequest(_ url: URL, senderPID: Int32?) -> UUID? {
        guard Self.accepts(url) else { return nil }
        let increment = nextSequence.addingReportingOverflow(1)
        guard !increment.overflow else { return nil }

        let id = makeID()
        captures.append(BufferedLinkCapture(
            id: id,
            sequence: nextSequence,
            url: url,
            senderPID: senderPID,
            receivedAt: now(),
            reopenedFromHistoryEntryID: nil
        ))
        nextSequence = increment.partialValue
        return id
    }

    @discardableResult
    func captureReopened(
        _ url: URL,
        id: UUID,
        receivedAt: Date,
        fromHistoryEntryID: UUID
    ) -> Bool {
        guard Self.accepts(url) else { return false }
        let increment = nextSequence.addingReportingOverflow(1)
        guard !increment.overflow else { return false }
        captures.append(BufferedLinkCapture(
            id: id,
            sequence: nextSequence,
            url: url,
            senderPID: nil,
            receivedAt: receivedAt,
            reopenedFromHistoryEntryID: fromHistoryEntryID
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

    func contains(requestID: UUID) -> Bool {
        captures.contains { $0.id == requestID }
    }

    @discardableResult
    func remove(requestID: UUID) -> Bool {
        guard let index = captures.firstIndex(where: { $0.id == requestID }) else {
            return false
        }
        captures.remove(at: index)
        return true
    }

    @discardableResult
    func removeFirst(ifSequenceMatches sequence: UInt64) -> Bool {
        guard captures.first?.sequence == sequence else { return false }
        captures.removeFirst()
        return true
    }

    nonisolated static func accepts(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

@MainActor
final class LinkIntakeService: LinkRoutingContinuationRequesting {
    enum UpdateTerminationError: Error, Equatable, LocalizedError {
        case startupNotReady
        case persistenceUnavailable
        case routingInProgress
        case pendingRequests

        var errorDescription: String? {
            switch self {
            case .startupNotReady: "Prism 还在启动或恢复数据，请稍后再安装更新。"
            case .persistenceUnavailable: "链接或历史记录尚未安全保存，请先处理存储提示。"
            case .routingInProgress: "正在处理链接，请完成后再安装更新。"
            case .pendingRequests: "还有待处理的链接，请先打开或取消这些链接。"
            }
        }
    }
    enum RecoveryState: Equatable, Sendable {
        case none
        case persistenceRetryRequired
        case routingResumeRequired
    }

    private struct PersistenceRetryFlight {
        let id: UUID
        let task: Task<Bool, Never>
    }

    private let queue: LinkRequestQueue
    private let bootstrap: BootstrapLinkBuffer
    private let sourceAttributor: any SourceAttributing
    private let lastActivatedSource: @MainActor () -> SourceApplication?
    private let diagnosticRecorder: (@MainActor (LinkCaptureDiagnostic) -> Void)?
    private let makeRequestID: @MainActor () -> UUID
    private let now: @MainActor () -> Date
    private weak var coordinator: (any LinkRoutingCoordinating)?
    private weak var warningPresenter: (any PersistenceWarningPresenting)?
    private var restorationFinished = false
    private var routingEnabled = false
    private var persistencePaused = false
    private var runtimeRoutingResumeRequired = false
    private var drainTask: Task<Void, Never>?
    private var routingTask: Task<Void, Never>?
    private var routingKickPending = false
    private var routingKickGeneration: UInt64 = 0
    private var persistenceRetryFlight: PersistenceRetryFlight?
    private var updateTerminationOriginalRoutingEnabled: Bool?
    private var updateTerminationGeneration: UUID?
    private var updateTerminationCheckpointReady = false
    private var updateTerminationCaptureArrived = false
    private var explicitCaptureOperationsInFlight = 0

    var isPreparingUpdateTermination: Bool { updateTerminationOriginalRoutingEnabled != nil }

    /// Read synchronously by applicationShouldTerminate, after the asynchronous
    /// queue check. A new event invalidates the checkpoint even after its save finishes.
    var canTerminateForUpdate: Bool {
        updateTerminationOriginalRoutingEnabled != nil
            && updateTerminationCheckpointReady
            && !updateTerminationCaptureArrived
            && bootstrap.first() == nil
            && drainTask == nil
            && routingTask == nil
            && explicitCaptureOperationsInFlight == 0
            && recoveryState == .none
            && coordinator?.hasInFlightOperations != true
    }

    func beginUpdateTermination() async throws {
        guard restorationFinished else { throw UpdateTerminationError.startupNotReady }
        guard recoveryState == .none else { throw UpdateTerminationError.persistenceUnavailable }
        guard updateTerminationOriginalRoutingEnabled == nil,
              routingTask == nil, explicitCaptureOperationsInFlight == 0,
              coordinator?.hasInFlightOperations != true
        else { throw UpdateTerminationError.routingInProgress }

        let generation = UUID()
        updateTerminationGeneration = generation
        updateTerminationOriginalRoutingEnabled = routingEnabled
        updateTerminationCaptureArrived = false
        routingEnabled = false
        routingKickPending = false
        do {
            // Finish saving captures without starting new browser launches. The
            // GetURL handler remains registered throughout and keeps accepting events.
            if bootstrap.first() != nil { startDrainWorkerIfNeeded(routeAfterDraining: false) }
            while let drainTask { await drainTask.value }
            guard updateTerminationGeneration == generation else { throw CancellationError() }
            guard recoveryState == .none else { throw UpdateTerminationError.persistenceUnavailable }
            guard routingTask == nil, explicitCaptureOperationsInFlight == 0,
                  coordinator?.hasInFlightOperations != true
            else { throw UpdateTerminationError.routingInProgress }
            let pending = await queue.snapshot()
            let terminal = await queue.terminalSnapshot()
            guard updateTerminationGeneration == generation else { throw CancellationError() }
            guard terminal.isEmpty else { throw UpdateTerminationError.persistenceUnavailable }
            guard pending.isEmpty, bootstrap.first() == nil, drainTask == nil,
                  !updateTerminationCaptureArrived
            else { throw UpdateTerminationError.pendingRequests }
            guard coordinator?.hasInFlightOperations != true,
                  explicitCaptureOperationsInFlight == 0, recoveryState == .none
            else { throw UpdateTerminationError.routingInProgress }
            updateTerminationCheckpointReady = true
        } catch {
            if updateTerminationGeneration == generation { cancelUpdateTermination() }
            throw error
        }
    }

    func cancelUpdateTermination() {
        guard let previousRoutingEnabled = updateTerminationOriginalRoutingEnabled else { return }
        updateTerminationOriginalRoutingEnabled = nil
        updateTerminationGeneration = nil
        updateTerminationCheckpointReady = false
        updateTerminationCaptureArrived = false
        routingEnabled = previousRoutingEnabled && !persistencePaused
        if bootstrap.first() != nil, !persistencePaused {
            startDrainWorkerIfNeeded(routeAfterDraining: routingEnabled)
        } else if routingEnabled {
            requestRoutingIfEnabled()
        }
    }
    private(set) var workerStartCount = 0
    private(set) var routingWorkerStartCount = 0

    var recoveryState: RecoveryState {
        if persistencePaused || persistenceRetryFlight != nil {
            return .persistenceRetryRequired
        }
        if runtimeRoutingResumeRequired {
            return .routingResumeRequired
        }
        return .none
    }

    init(
        queue: LinkRequestQueue,
        bootstrap: BootstrapLinkBuffer,
        sourceAttributor: any SourceAttributing,
        lastActivatedSource: @escaping @MainActor () -> SourceApplication?,
        coordinator: (any LinkRoutingCoordinating)? = nil,
        warningPresenter: (any PersistenceWarningPresenting)? = nil,
        diagnosticRecorder: (@MainActor (LinkCaptureDiagnostic) -> Void)? = nil,
        makeRequestID: @escaping @MainActor () -> UUID = UUID.init,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.queue = queue
        self.bootstrap = bootstrap
        self.sourceAttributor = sourceAttributor
        self.lastActivatedSource = lastActivatedSource
        self.coordinator = coordinator
        self.warningPresenter = warningPresenter
        self.diagnosticRecorder = diagnosticRecorder
        self.makeRequestID = makeRequestID
        self.now = now
    }

    @discardableResult
    func capture(url: URL, senderPID: Int32?) -> Bool {
        captureRequest(url: url, senderPID: senderPID) != nil
    }

    @discardableResult
    func captureRequest(url: URL, senderPID: Int32?) -> UUID? {
        let requestID = bootstrap.captureRequest(url, senderPID: senderPID)
        if requestID != nil, updateTerminationOriginalRoutingEnabled != nil {
            updateTerminationCaptureArrived = true
        }
        if requestID != nil, restorationFinished, !persistencePaused {
            startDrainWorkerIfNeeded(routeAfterDraining: routingEnabled)
        }
        return requestID
    }

    func captureForExplicitSelection(url: URL, senderPID: Int32?) async -> UUID? {
        guard updateTerminationOriginalRoutingEnabled == nil else { return nil }
        explicitCaptureOperationsInFlight += 1
        defer { explicitCaptureOperationsInFlight -= 1 }
        guard restorationFinished, !routingEnabled, !persistencePaused,
              BootstrapLinkBuffer.accepts(url)
        else {
            return nil
        }
        while let drainTask {
            await drainTask.value
        }
        guard !persistencePaused, bootstrap.first() == nil else {
            return nil
        }

        let request = LinkRequest(
            id: UUID(),
            url: url,
            receivedAt: Date(),
            source: sourceAttributor.resolve(
                senderPID: senderPID,
                lastActivated: lastActivatedSource()
            )
        )
        do {
            return try await queue.enqueueIfNoPending(request) ? request.id : nil
        } catch {
            warningPresenter?.present(.recoveryStoreUnavailable)
            return nil
        }
    }

    /// Reopens only the exact safe URL retained by History. It never performs source
    /// attribution and always appends behind existing durable requests.
    func enqueueReopened(url: URL, fromHistoryEntryID: UUID) async -> LinkRequest? {
        guard updateTerminationOriginalRoutingEnabled == nil else { return nil }
        explicitCaptureOperationsInFlight += 1
        defer { explicitCaptureOperationsInFlight -= 1 }
        guard restorationFinished, !persistencePaused,
              BootstrapLinkBuffer.accepts(url),
              URLSanitizer.default.sanitize(url)?.absoluteString == url.absoluteString
        else {
            return nil
        }

        let request = LinkRequest(
            id: makeRequestID(),
            url: url,
            receivedAt: now(),
            source: .unknown,
            reopenedFromHistoryEntryID: fromHistoryEntryID
        )
        guard bootstrap.captureReopened(
            url,
            id: request.id,
            receivedAt: request.receivedAt,
            fromHistoryEntryID: fromHistoryEntryID
        ) else {
            return nil
        }

        startDrainWorkerIfNeeded(routeAfterDraining: routingEnabled)
        while let drainTask {
            await drainTask.value
        }
        guard !bootstrap.contains(requestID: request.id) else {
            bootstrap.remove(requestID: request.id)
            return nil
        }
        return request
    }

    func finishRestorationAndStartDraining(routeAfterDraining: Bool = true) {
        guard !restorationFinished else { return }
        restorationFinished = true
        routingEnabled = routeAfterDraining
        runtimeRoutingResumeRequired = false
        reportRecoveryState()
        startDrainWorkerIfNeeded(routeAfterDraining: routeAfterDraining)
    }

    @discardableResult
    func resumeRoutingAfterRecoveryUserAction() async -> Bool {
        guard updateTerminationOriginalRoutingEnabled == nil, restorationFinished,
              !routingEnabled,
              !persistencePaused,
              drainTask == nil,
              routingTask == nil,
              bootstrap.first() == nil
        else {
            return false
        }
        routingEnabled = true
        runtimeRoutingResumeRequired = false
        reportRecoveryState()
        requestRoutingIfEnabled()
        while let routingTask {
            await routingTask.value
        }
        return true
    }

    @discardableResult
    func retryPendingPersistenceAfterUserAction() async -> Bool {
        if let persistenceRetryFlight {
            return await persistenceRetryFlight.task.value
        }
        guard restorationFinished, persistencePaused, bootstrap.first() != nil else {
            return false
        }
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            self.persistencePaused = false
            self.routingEnabled = false
            self.reportRecoveryState()
            self.startDrainWorkerIfNeeded(routeAfterDraining: false)
            await self.waitForPersistenceForTesting()
            let succeeded = !self.persistencePaused && self.bootstrap.first() == nil
            if succeeded {
                self.runtimeRoutingResumeRequired = true
            }
            return succeeded
        }
        persistenceRetryFlight = PersistenceRetryFlight(id: id, task: task)
        reportRecoveryState()
        let succeeded = await task.value
        if persistenceRetryFlight?.id == id {
            persistenceRetryFlight = nil
        }
        reportRecoveryState()
        return succeeded
    }

    func requestRoutingContinuation() {
        requestRoutingIfEnabled()
    }

    func drainForTesting() async throws {
        while let drainTask {
            await drainTask.value
        }
        try await drainBufferedLinks()
        _ = await coordinator?.processNext()
    }

    func waitForDrainForTesting() async {
        while drainTask != nil || routingTask != nil {
            if let drainTask {
                await drainTask.value
            }
            if let routingTask {
                await routingTask.value
            }
        }
    }

    func waitForPersistenceForTesting() async {
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
            } catch {
                failed = true
                routingEnabled = false
                persistencePaused = true
                runtimeRoutingResumeRequired = false
                routingKickPending = false
                reportRecoveryState()
            }
            drainTask = nil
            if !failed, restorationFinished, bootstrap.first() != nil {
                startDrainWorkerIfNeeded(
                    routeAfterDraining: routeAfterDraining && routingEnabled
                )
            } else if !failed, routeAfterDraining {
                requestRoutingIfEnabled()
            }
        }
    }

    private func requestRoutingIfEnabled() {
        guard routingEnabled, !persistencePaused else { return }
        routingKickPending = true
        routingKickGeneration &+= 1
        startRoutingWorkerIfNeeded()
    }

    private func startRoutingWorkerIfNeeded() {
        guard routingTask == nil else { return }
        routingWorkerStartCount += 1
        routingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while routingEnabled, !persistencePaused, routingKickPending {
                routingKickPending = false
                let passGeneration = routingKickGeneration
                let disposition = await coordinator?.processNext(while: { [weak self] in
                    self?.routingEnabled == true && self?.persistencePaused == false
                }) ?? .drained
                guard routingEnabled, !persistencePaused else {
                    routingKickPending = false
                    break
                }
                switch disposition {
                case .paused:
                    routingKickPending = false
                case .busy:
                    routingKickPending = routingKickGeneration != passGeneration
                case .moreWork:
                    routingKickPending = routingEnabled && !persistencePaused
                case .drained:
                    routingKickPending = await hasQueuedRequestFromNewerKick(
                        than: passGeneration
                    )
                }
            }
            routingTask = nil
            if routingEnabled, !persistencePaused, routingKickPending {
                startRoutingWorkerIfNeeded()
            }
        }
    }

    private func hasQueuedRequestFromNewerKick(than passGeneration: UInt64) async -> Bool {
        while true {
            let generationBeforeSnapshot = routingKickGeneration
            guard generationBeforeSnapshot != passGeneration else { return false }
            let requests = await queue.snapshot()
            guard generationBeforeSnapshot == routingKickGeneration else { continue }
            return requests.contains { $0.state == .queued }
        }
    }

    private func drainBufferedLinks() async throws {
        while let capture = bootstrap.first() {
            let source = capture.reopenedFromHistoryEntryID == nil
                ? sourceAttributor.resolve(
                    senderPID: capture.senderPID,
                    lastActivated: lastActivatedSource()
                )
                : .unknown
            let request = LinkRequest(
                id: capture.id,
                url: capture.url,
                receivedAt: capture.receivedAt,
                source: source,
                reopenedFromHistoryEntryID: capture.reopenedFromHistoryEntryID
            )
            guard try await queue.enqueue(request) else {
                throw LinkIntakeError.duplicateRequestID(request.id)
            }
            guard bootstrap.removeFirst(ifSequenceMatches: capture.sequence) else {
                continue
            }
            if capture.reopenedFromHistoryEntryID == nil {
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

    private func reportRecoveryState() {
        if let presenter = warningPresenter as? any RuntimeLinkPersistenceWarningPresenting {
            presenter.updateRuntimeLinkRecoveryState(RuntimeLinkRecoveryState(recoveryState))
        } else if recoveryState == .persistenceRetryRequired {
            warningPresenter?.present(.recoveryStoreUnavailable)
        }
    }
}
