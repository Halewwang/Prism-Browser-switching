import AppKit
import Foundation
import Observation

@MainActor @Observable
final class InAppUpdateSession {
    enum Stage: Equatable { case available, downloading, ready, installing, failed }
    let installer: GitHubPublishedInstaller
    private(set) var stage: Stage = .available
    private(set) var progress: Double?
    private(set) var message: String?
    private var prepared: PreparedUpdate?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var downloadID: UUID?
    @ObservationIgnored private var cancelInstallation: (@MainActor () -> Void)?
    @ObservationIgnored private var installationCommitted = false
    @ObservationIgnored private let prepare: @MainActor (GitHubPublishedInstaller, @escaping @Sendable (Double?) -> Void) async throws -> PreparedUpdate
    @ObservationIgnored private let cleanup: @MainActor (PreparedUpdate) -> Void
    @ObservationIgnored private let startInstallation: @MainActor (PreparedUpdate) async throws -> (@MainActor () -> Void)
    @ObservationIgnored private let prepareTermination: @MainActor () async throws -> Void
    @ObservationIgnored private let cancelTermination: @MainActor () -> Void
    @ObservationIgnored private let terminate: @MainActor () -> Void
    @ObservationIgnored private let commitInstallation: @MainActor () throws -> Void
    @ObservationIgnored private let onEvent: @MainActor (UpdateEvent) -> Void

    var hasPreparedInstallation: Bool { cancelInstallation != nil }

    init(
        installer: GitHubPublishedInstaller,
        prepare: @escaping @MainActor (GitHubPublishedInstaller, @escaping @Sendable (Double?) -> Void) async throws -> PreparedUpdate,
        cleanup: @escaping @MainActor (PreparedUpdate) -> Void,
        startInstallation: @escaping @MainActor (PreparedUpdate) async throws -> (@MainActor () -> Void),
        prepareTermination: @escaping @MainActor () async throws -> Void,
        cancelTermination: @escaping @MainActor () -> Void,
        terminate: @escaping @MainActor () -> Void,
        commitInstallation: @escaping @MainActor () throws -> Void = {},
        onEvent: @escaping @MainActor (UpdateEvent) -> Void = { _ in }
    ) {
        self.installer = installer
        self.prepare = prepare
        self.cleanup = cleanup
        self.startInstallation = startInstallation
        self.prepareTermination = prepareTermination
        self.cancelTermination = cancelTermination
        self.terminate = terminate
        self.commitInstallation = commitInstallation
        self.onEvent = onEvent
    }

    func startDownload() {
        guard operation == nil, stage == .available || stage == .failed else { return }
        operation = Task { defer { operation = nil }; await download() }
    }
    func startInstall() {
        guard operation == nil, stage == .ready else { return }
        operation = Task { defer { operation = nil }; await install() }
    }

    func download() async {
        guard stage == .available || stage == .failed else { return }
        let id = UUID()
        downloadID = id
        stage = .downloading
        message = nil
        progress = nil
        onEvent(.downloading(progress: nil))
        do {
            let result = try await prepare(installer) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.downloadID == id, self.stage == .downloading else { return }
                    self.progress = value.map { min(max($0, 0), 1) }
                    self.onEvent(.downloading(progress: self.progress))
                }
            }
            guard !Task.isCancelled, downloadID == id else {
                cleanup(result)
                throw CancellationError()
            }
            prepared = result
            downloadID = nil
            stage = .ready
            onEvent(.readyToInstall)
        } catch is CancellationError {
            downloadID = nil
            stage = .available
            progress = nil
            onEvent(.cancelled)
        } catch {
            downloadID = nil
            stage = .failed
            message = error.localizedDescription
            onEvent(.failed(.system(error.localizedDescription)))
        }
    }

    func install() async {
        guard stage == .ready, let prepared else { return }
        stage = .installing
        message = nil
        do {
            cancelInstallation = try await startInstallation(prepared)
            try Task.checkCancellation()
            try await prepareTermination()
            try Task.checkCancellation()
            // No suspension between the final gate and AppKit's synchronous
            // applicationShouldTerminate checkpoint in the delegate.
            terminate()
        } catch {
            cancelPreparedInstallation(message: error.localizedDescription)
        }
    }

    func cancelPreparedInstallation(message: String) {
        cancelInstallation?()
        cancelInstallation = nil
        cancelTermination()
        stage = prepared == nil ? .failed : .ready
        self.message = message
        onEvent(.failed(.system(message)))
    }

    func commitPreparedInstallation() throws {
        guard hasPreparedInstallation, stage == .installing else { throw CocoaError(.userCancelled) }
        try commitInstallation()
        installationCommitted = true
    }

    func cancelDownload() { operation?.cancel() }

    func dispose() {
        // AppKit can close this window during normal application termination.
        // The committed helper now owns its workspace and must finish independently.
        guard !installationCommitted else { return }
        operation?.cancel()
        downloadID = nil
        cancelInstallation?()
        cancelInstallation = nil
        if stage == .installing { cancelTermination() }
        if let prepared { cleanup(prepared) }
        prepared = nil
    }

    func revealInstaller() {
        guard let prepared else { return }
        NSWorkspace.shared.activateFileViewerSelecting([prepared.installerFileURL])
    }
}
