import Foundation
import Darwin

@MainActor
protocol UpdateInstallationCoordinating {
    func currentInstallationURL() throws -> URL
    func prepareInstallation(_ prepared: PreparedUpdate, targetURL: URL, parentPID: Int32) async throws -> PreparedInstallation
}

extension UpdateInstallationCoordinating {
    func currentInstallationURL() throws -> URL { Bundle.main.bundleURL }
}

@MainActor
final class PreparedInstallation {
    private let plan: UpdateInstallationPlan
    // Retain the Process through application termination, but never kill the
    // application or installer. Cancellation is a protected file handshake.
    private let process: Process
    init(plan: UpdateInstallationPlan, process: Process) { self.plan = plan; self.process = process }
    func commit() throws {
        guard process.isRunning, !FileManager.default.fileExists(atPath: plan.cancelURL.path) else { throw UpdateInstallationError.helperFailed("安装准备已取消，请重试。") }
        try Data(plan.id.uuidString.utf8).write(to: plan.commitURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plan.commitURL.path)
    }
    func cancel() {
        try? Data("cancel".utf8).write(to: plan.cancelURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plan.cancelURL.path)
    }
}

@MainActor
final class NativeUpdateInstallationCoordinator: UpdateInstallationCoordinating {
    private let currentBundleURL: URL
    private let helperURL: URL
    private let handshakeTimeout: TimeInterval
    init(currentBundleURL: URL = Bundle.main.bundleURL, helperURL: URL? = nil, handshakeTimeout: TimeInterval = 30) {
        self.currentBundleURL = currentBundleURL
        self.helperURL = (helperURL ?? currentBundleURL.appendingPathComponent("Contents/Helpers/PrismUpdateInstaller")).resolvingSymlinksInPath()
        self.handshakeTimeout = handshakeTimeout
    }

    func prepareInstallation(_ prepared: PreparedUpdate, targetURL: URL, parentPID: Int32) async throws -> PreparedInstallation {
        guard parentPID == getpid(),
              FileManager.default.isExecutableFile(atPath: helperURL.path),
              helperURL.lastPathComponent == "PrismUpdateInstaller" else { throw UpdateInstallationError.helperUnavailable }
        // A path hint can only resolve the original installed app after the
        // kernel guest and its complete signed code match that writable target.
        let installedURL = try InstallerLaunchValidation.currentInstallationURL(bundleURL: currentBundleURL, pid: parentPID)
        guard targetURL.standardizedFileURL == installedURL.standardizedFileURL else { throw UpdateInstallationError.parentMismatch }
        _ = try InstallerSystem.run("/usr/bin/codesign", ["--verify", "--strict", helperURL.path])
        let parent = try InstallerSystem.parentIdentity(pid: parentPID)
        try InstallerLaunchValidation.validateRunningApplication(pid: parentPID, targetURL: targetURL, expectedVersion: InstallerSystem.version(targetURL))
        try InstallerSystem.requireUpgrade(prepared.version, from: InstallerSystem.version(targetURL))
        let workspace = prepared.workspaceURL.resolvingSymlinksInPath()
        try InstallerSystem.validateControlDirectory(workspace)
        let plan = UpdateInstallationPlan(id: UUID(), workspaceURL: workspace, applicationURL: prepared.applicationURL, targetURL: targetURL, version: prepared.version, parent: parent, installerFileURL: prepared.installerFileURL)
        try FileManager.default.createDirectory(at: plan.controlURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let planURL = plan.controlURL.appendingPathComponent("plan.json")
        try JSONEncoder().encode(plan).write(to: planURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: planURL.path)
        let process = Process()
        process.executableURL = helperURL
        process.arguments = [planURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let handle = PreparedInstallation(plan: plan, process: process)
        let deadline = Date().addingTimeInterval(handshakeTimeout)
        do {
            while !FileManager.default.fileExists(atPath: plan.readyURL.path) {
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath: plan.receiptURL.path), let receipt = try? JSONDecoder().decode(UpdateInstallationReceipt.self, from: Data(contentsOf: plan.receiptURL)) {
                    throw UpdateInstallationError.helperFailed(receipt.message)
                }
                guard process.isRunning else { throw UpdateInstallationError.helperFailed("安装助手无法准备更新，当前应用保持运行，请手动安装。") }
                guard Date() < deadline else { throw UpdateInstallationError.handshakeTimedOut }
                try await Task.sleep(for: .milliseconds(100))
            }
            try Task.checkCancellation()
            guard process.isRunning else { throw UpdateInstallationError.helperFailed("安装准备已取消，请重试。") }
            return handle
        } catch { handle.cancel(); throw error }
    }
}
