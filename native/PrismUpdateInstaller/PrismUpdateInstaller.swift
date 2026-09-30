import Foundation
import AppKit
import Darwin

@main struct PrismUpdateInstaller {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw UpdateInstallationError.unsafePath }
            let planURL = URL(fileURLWithPath: CommandLine.arguments[1])
            try InstallerSystem.validateControlDirectory(planURL.deletingLastPathComponent())
            let attributes = try FileManager.default.attributesOfItem(atPath: planURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  planURL.path == planURL.resolvingSymlinksInPath().path,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0,
                  (attributes[.size] as? NSNumber)?.intValue ?? 0 < 16384 else { throw UpdateInstallationError.unsafePath }
            let plan = try JSONDecoder().decode(UpdateInstallationPlan.self, from: Data(contentsOf: planURL))
            guard planURL == plan.controlURL.appendingPathComponent("plan.json") else { throw UpdateInstallationError.unsafePath }
            try InstallerSystem.validateControlDirectory(plan.workspaceURL)
            let success = await install(plan)
            exit(success ? 0 : 1)

        } catch { exit(1) }
    }
    private static func install(_ originalPlan: UpdateInstallationPlan) async -> Bool {
        let operations = SystemInstallerOperations()
        let mount = originalPlan.controlURL.appendingPathComponent("archive-mount")
        var attemptedMount = false
        defer {
            if attemptedMount {
                if (try? InstallerSystem.run("/usr/bin/hdiutil", ["detach", mount.path])) == nil {
                    _ = try? InstallerSystem.run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
                }
            }
        }
        do {
            try operations.validateParent(originalPlan.parent, targetURL: originalPlan.targetURL)
            try InstallerSystem.requireUpgrade(originalPlan.version, from: InstallerSystem.version(originalPlan.targetURL))
            guard let archive = originalPlan.installerFileURL else { throw UpdateInstallationError.invalidApplication }
            let manifest = try UpdateArchiveVerification.verify(workspace: originalPlan.workspaceURL, archiveURL: archive, expectedVersion: originalPlan.version)
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            attemptedMount = true
            _ = try InstallerSystem.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, archive.path])
            var plan = originalPlan
            plan.applicationURL = mount.appendingPathComponent("Prism.app")
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plan.applicationURL.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
            guard plist?["LSMinimumSystemVersion"] as? String == manifest.minimumSystemVersion else { throw UpdateInstallationError.invalidApplication }
            let receipt = await UpdateInstallerEngine(operations: operations).run(plan)
            // Explicit detach before exit; exit() does not run Swift defer blocks.
            if (try? InstallerSystem.run("/usr/bin/hdiutil", ["detach", mount.path])) != nil { attemptedMount = false }
            return receipt.status == .installed
        } catch {
            if !FileManager.default.fileExists(atPath: originalPlan.receiptURL.path) {
                let receipt = UpdateInstallationReceipt(status: .failed, message: error.localizedDescription, version: originalPlan.version, date: Date())
                try? operations.writeReceipt(receipt, plan: originalPlan)
            }
            return false
        }
    }

}

struct SystemInstallerOperations: UpdateInstallerOperations {
    func validateApplication(_ url: URL, expectedVersion: String?) throws { try InstallerSystem.validateApplication(url, expectedVersion: expectedVersion) }
    func validateParent(_ expected: InstallerParentIdentity, targetURL: URL) throws {
        guard expected.userID == getuid(), try InstallerSystem.parentIdentity(pid: expected.pid) == expected else { throw UpdateInstallationError.parentMismatch }
        try InstallerLaunchValidation.validateRunningApplication(pid: expected.pid, targetURL: targetURL, expectedVersion: InstallerSystem.version(targetURL))
    }
    func applicationFingerprint(_ url: URL) throws -> Data { try InstallerLaunchValidation.diskFingerprint(url) }
    func validateUpgrade(_ version: String, currentURL: URL) throws { try InstallerSystem.requireUpgrade(version, from: InstallerSystem.version(currentURL)) }
    func parentState(_ expected: InstallerParentIdentity) -> InstallerParentState {
        if kill(expected.pid, 0) != 0 && errno == ESRCH { return .exited }
        guard let current = try? InstallerSystem.parentIdentity(pid: expected.pid), current == expected else { return .reused }
        return .running
    }
    func copyApplication(from: URL, to: URL) throws {
        // ditto preserves resource forks, extended attributes and quarantine.
        _ = try InstallerSystem.run("/usr/bin/ditto", ["--rsrc", "--extattr", "--acl", from.path, to.path])
        // The trusted DMG is mounted afresh, so retain a quarantine marker on
        // the copied app even if its archived root does not contain one.
        let quarantine = "0081;" + String(Int(Date().timeIntervalSince1970), radix: 16) + ";Prism;" + UUID().uuidString
        _ = try InstallerSystem.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", quarantine, to.path])
    }
    func moveItem(from: URL, to: URL) throws { try FileManager.default.moveItem(at: from, to: to) }
    @MainActor func launch(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.environment = [InstallerLaunchValidation.installedPathEnvironmentKey: url.path]
        let application = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        let deadline = Date().addingTimeInterval(30)
        while !application.isFinishedLaunching {
            guard !application.isTerminated, Date() < deadline else {
                throw UpdateInstallationError.helperFailed("新版未能完成启动，正在恢复原应用。")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // LaunchServices can return before AppKit startup, or before an early
        // crash/exit. Keep the backup until startup finishes and remains alive.
        try await Task.sleep(for: .seconds(2))
        guard !application.isTerminated else {
            throw UpdateInstallationError.helperFailed("新版在启动时退出，正在恢复原应用。")
        }
        try InstallerLaunchValidation.validateRunningApplication(pid: application.processIdentifier, targetURL: url, expectedVersion: InstallerSystem.version(url))
        guard !application.isTerminated else { throw UpdateInstallationError.invalidApplication }
    }
    func signalReady(_ plan: UpdateInstallationPlan) throws {
        try Data("ready".utf8).write(to: plan.readyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plan.readyURL.path)
    }
    func isCancelled(_ plan: UpdateInstallationPlan) -> Bool { FileManager.default.fileExists(atPath: plan.cancelURL.path) }
    func isCommitted(_ plan: UpdateInstallationPlan) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: plan.commitURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              plan.commitURL.path == plan.commitURL.resolvingSymlinksInPath().path,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0,
              (attributes[.size] as? NSNumber)?.intValue == plan.id.uuidString.utf8.count,
              let bytes = try? Data(contentsOf: plan.commitURL) else { return false }
        return bytes == Data(plan.id.uuidString.utf8)
    }
    func writeReceipt(_ receipt: UpdateInstallationReceipt, plan: UpdateInstallationPlan) throws {
        try JSONEncoder().encode(receipt).write(to: plan.receiptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plan.receiptURL.path)
    }
}
