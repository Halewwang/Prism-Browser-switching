import Foundation

struct InstallerParentIdentity: Codable, Sendable, Equatable {
    let pid: Int32
    let startTime: String
    let executablePath: String
    let userID: UInt32
}

enum InstallerParentState: Sendable { case running, exited, reused }

struct UpdateInstallationPlan: Codable, Sendable {
    let id: UUID
    var workspaceURL: URL
    var applicationURL: URL
    var targetURL: URL
    let version: String
    let parent: InstallerParentIdentity
    var installerFileURL: URL? = nil
    var controlURL: URL { workspaceURL.appendingPathComponent("installation-\(id.uuidString)") }
    var readyURL: URL { controlURL.appendingPathComponent("ready") }
    var commitURL: URL { controlURL.appendingPathComponent("commit") }
    var cancelURL: URL { controlURL.appendingPathComponent("cancel") }
    var receiptURL: URL { controlURL.appendingPathComponent("receipt.json") }
    var stageURL: URL { targetURL.deletingLastPathComponent().appendingPathComponent(".Prism-update-\(id.uuidString).app") }
    var backupURL: URL { targetURL.deletingLastPathComponent().appendingPathComponent(".Prism-backup-\(id.uuidString).app") }
}

struct UpdateInstallationReceipt: Codable, Sendable {
    enum Status: String, Codable, Sendable { case installed, cancelled, failed, rolledBack, recoveryRequired }
    let status: Status
    let message: String
    let version: String
    let date: Date
}

protocol UpdateInstallerOperations: Sendable {
    func validateApplication(_ url: URL, expectedVersion: String?) throws
    func validateParent(_ expected: InstallerParentIdentity, targetURL: URL) throws
    func applicationFingerprint(_ url: URL) throws -> Data
    func validateUpgrade(_ version: String, currentURL: URL) throws
    func parentState(_ expected: InstallerParentIdentity) -> InstallerParentState
    func copyApplication(from: URL, to: URL) throws
    func moveItem(from: URL, to: URL) throws
    func launch(_ url: URL) async throws
    func signalReady(_ plan: UpdateInstallationPlan) throws
    func isCancelled(_ plan: UpdateInstallationPlan) -> Bool
    func isCommitted(_ plan: UpdateInstallationPlan) -> Bool
    func writeReceipt(_ receipt: UpdateInstallationReceipt, plan: UpdateInstallationPlan) throws
}

enum UpdateInstallationError: Error, LocalizedError {
    case unsafePath, invalidApplication, invalidVersion, parentMismatch, notWritable, helperUnavailable, helperFailed(String), handshakeTimedOut
    var errorDescription: String? {
        switch self {
        case .unsafePath: "应用位置不支持自动更新，请将 Prism 放入可写的正常应用目录。"
        case .invalidApplication: "更新包的应用身份、系统要求或代码签名无效。"
        case .invalidVersion: "更新包的版本不高于当前版本。"
        case .parentMismatch: "运行中的应用与安装目标不一致，更新已取消。"
        case .notWritable: "没有应用目录的写入权限，请手动安装更新。"
        case .helperUnavailable: "安装助手缺失或无效，请手动安装更新。"
        case .helperFailed(let message): message
        case .handshakeTimedOut: "准备安装超时，当前应用保持运行，请重试或手动安装。"
        }
    }
}

/// The only replacement transaction. All destructive operations occur after the
/// exact original parent exits; a reused PID is cancellation, never permission.
struct UpdateInstallerEngine: Sendable {
    let operations: any UpdateInstallerOperations
    var waitTimeout: TimeInterval = 60
    var pollInterval: TimeInterval = 0.1

    func run(_ plan: UpdateInstallationPlan) async -> UpdateInstallationReceipt {
        let files = FileManager.default
        var backupMade = false
        var replacementMade = false
        var stageOwned = false
        var receipt: UpdateInstallationReceipt
        do {
            try validatePaths(plan)
            let targetFingerprint = try operations.applicationFingerprint(plan.targetURL)
            try operations.validateParent(plan.parent, targetURL: plan.targetURL)
            guard try operations.applicationFingerprint(plan.targetURL) == targetFingerprint else { throw UpdateInstallationError.invalidApplication }
            try operations.validateUpgrade(plan.version, currentURL: plan.targetURL)
            let targetIdentity = try directoryIdentity(plan.targetURL)
            try operations.validateApplication(plan.targetURL, expectedVersion: nil)
            try operations.validateApplication(plan.applicationURL, expectedVersion: plan.version)
            guard !operations.isCancelled(plan) else { throw InstallerCancellation() }
            guard !files.fileExists(atPath: plan.stageURL.path), !files.fileExists(atPath: plan.backupURL.path) else { throw UpdateInstallationError.unsafePath }
            stageOwned = true
            try operations.copyApplication(from: plan.applicationURL, to: plan.stageURL)
            try operations.validateApplication(plan.stageURL, expectedVersion: plan.version)
            try validatePaths(plan)
            try operations.signalReady(plan)

            let deadline = Date().addingTimeInterval(waitTimeout)
            while true {
                if operations.isCancelled(plan) { throw InstallerCancellation() }
                switch operations.parentState(plan.parent) {
                case .exited: break
                case .reused: throw InstallerCancellation()
                case .running:
                    guard Date() < deadline else { throw InstallerCancellation() }
                    try await Task.sleep(for: .seconds(pollInterval))
                    continue
                }
                break
            }
            guard operations.isCommitted(plan) else { throw InstallerCancellation() }
            guard try directoryIdentity(plan.targetURL) == targetIdentity else { throw UpdateInstallationError.unsafePath }
            // Recheck after waiting so a changed target or symlink cannot reuse
            // earlier validation to redirect the replacement.
            try validatePaths(plan)
            try operations.validateApplication(plan.targetURL, expectedVersion: nil)
            try operations.validateApplication(plan.stageURL, expectedVersion: plan.version)
            guard try operations.applicationFingerprint(plan.targetURL) == targetFingerprint else { throw UpdateInstallationError.invalidApplication }
            try operations.validateUpgrade(plan.version, currentURL: plan.targetURL)
            guard !operations.isCancelled(plan) else { throw InstallerCancellation() }
            try operations.moveItem(from: plan.targetURL, to: plan.backupURL)
            backupMade = true
            try operations.moveItem(from: plan.stageURL, to: plan.targetURL)
            replacementMade = true
            try await operations.launch(plan.targetURL)
            // A successful LaunchServices request is not a functional health check.
            try? files.removeItem(at: plan.backupURL)
            backupMade = false
            receipt = result(.installed, "新版已启动。", plan)
        } catch {
            if backupMade {
                do {
                    if replacementMade { try files.removeItem(at: plan.targetURL) }
                    try operations.moveItem(from: plan.backupURL, to: plan.targetURL)
                    backupMade = false
                    try? await operations.launch(plan.targetURL)
                    receipt = result(.rolledBack, "更新失败，已恢复原应用：\(error.localizedDescription)", plan)
                } catch {
                    // Preserve the backup if recovery itself fails. Never delete
                    // the user's last valid copy during error cleanup.
                    receipt = result(.recoveryRequired, "更新失败，原应用保留在 \(plan.backupURL.path)，需要手动恢复：\(error.localizedDescription)", plan)
                }
            } else if error is InstallerCancellation || error is CancellationError {
                receipt = result(.cancelled, "更新已取消，原应用保持不变。", plan)
            } else {
                receipt = result(.failed, error.localizedDescription, plan)
            }
        }
        if stageOwned { try? files.removeItem(at: plan.stageURL) }
        try? operations.writeReceipt(receipt, plan: plan)
        return receipt
    }

    private func result(_ status: UpdateInstallationReceipt.Status, _ message: String, _ plan: UpdateInstallationPlan) -> UpdateInstallationReceipt {
        .init(status: status, message: message, version: plan.version, date: Date())
    }

    private func validatePaths(_ plan: UpdateInstallationPlan) throws {
        let files = FileManager.default
        for url in [plan.workspaceURL, plan.applicationURL, plan.targetURL] {
            guard url.isFileURL, url.path == url.standardizedFileURL.path,
                  !url.pathComponents.contains("AppTranslocation"),
                  !url.pathComponents.contains("Volumes") else { throw UpdateInstallationError.unsafePath }
            // /tmp and /var are system aliases; callers must pass resolved URLs.
            guard url.path == url.resolvingSymlinksInPath().path else { throw UpdateInstallationError.unsafePath }
        }
        let workspacePrefix = plan.workspaceURL.path + "/"
        guard plan.applicationURL.path.hasPrefix(workspacePrefix),
              plan.targetURL.lastPathComponent == "Prism.app",
              !plan.targetURL.path.hasPrefix(workspacePrefix),
              files.fileExists(atPath: plan.targetURL.path),
              files.fileExists(atPath: plan.applicationURL.path) else { throw UpdateInstallationError.unsafePath }
        let parent = plan.targetURL.deletingLastPathComponent()
        let values = try parent.resourceValues(forKeys: [.volumeIsReadOnlyKey, .isDirectoryKey])
        guard values.isDirectory == true, values.volumeIsReadOnly != true,
              files.isWritableFile(atPath: parent.path), files.isWritableFile(atPath: plan.targetURL.path) else { throw UpdateInstallationError.notWritable }
        try rejectSymlinks(in: plan.applicationURL)
        try rejectSymlinks(in: plan.targetURL)
        if files.fileExists(atPath: plan.stageURL.path) { try rejectSymlinks(in: plan.stageURL) }
    }

    private func directoryIdentity(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return "\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
    }

    private func rejectSymlinks(in root: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { throw UpdateInstallationError.unsafePath }
        for case let entry as URL in enumerator {
            guard try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw UpdateInstallationError.unsafePath }
        }
    }
}

private struct InstallerCancellation: Error { }
