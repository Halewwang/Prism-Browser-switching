import Foundation
import Testing
@testable import PrismNative

@Suite("Transactional update installation")
struct UpdateInstallationTests {
    @Test func onlyExplicitConsentRemovesQuarantineFromVerifiedReplacement() async throws {
        for consent: Bool? in [nil, false, true] {
            let fixture = try InstallerFixture()
            defer { fixture.remove() }
            _ = try InstallerSystem.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;00000000;Prism;test", fixture.plan.applicationURL.path])
            var candidatePlan = fixture.plan
            candidatePlan.allowUnnotarizedPublicTestUpdate = consent
            let plan = try JSONDecoder().decode(UpdateInstallationPlan.self, from: JSONEncoder().encode(candidatePlan))
            let result = await UpdateInstallerEngine(operations: fixture.operations).run(plan)
            #expect(result.status == .installed)
            let quarantine = try? InstallerSystem.run("/usr/bin/xattr", ["-p", "com.apple.quarantine", fixture.target.path])
            #expect((quarantine == nil) == (consent == true))
        }
    }

    @Test func rejectsCandidateOutsideWorkspaceBeforeCopying() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        var plan = fixture.plan
        plan.applicationURL = fixture.root.appendingPathComponent("outside.app")
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(plan)
        #expect(result.status == .failed)
        #expect(try String(contentsOf: fixture.target.appendingPathComponent("marker"), encoding: .utf8) == "old")
        #expect(!fixture.operations.didCopy)
    }

    @Test func rejectsSymlinkTargetAndVolumesBeforeCopying() async throws {
        for volumes in [false, true] {
            let fixture = try InstallerFixture()
            defer { fixture.remove() }
            var plan = fixture.plan
            if volumes {
                plan.targetURL = URL(fileURLWithPath: "/Volumes/Prism/Prism.app")
            } else {
                let alias = fixture.root.appendingPathComponent("alias")
                try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
                plan.targetURL = alias.appendingPathComponent("Prism.app")
            }
            let result = await UpdateInstallerEngine(operations: fixture.operations).run(plan)
            #expect(result.status == .failed)
            #expect(!fixture.operations.didCopy)
        }
    }

    @Test func waitingTimeoutNeverReplacesRunningApplication() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        fixture.operations.parentStaysAlive = true
        let result = await UpdateInstallerEngine(operations: fixture.operations, waitTimeout: 0.04, pollInterval: 0.01).run(fixture.plan)
        #expect(result.status == .cancelled)
        #expect(fixture.operations.didSignalReady)
        #expect(try fixture.marker() == "old")
        #expect(!FileManager.default.fileExists(atPath: fixture.backup.path))
    }

    @Test func reusedPIDCancelsWithoutReplacing() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        fixture.operations.reusedPID = true
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .cancelled)
        #expect(try fixture.marker() == "old")
    }

    @Test func copyFailureKeepsOldApplicationAndNeverSignalsReady() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        fixture.operations.failCopy = true
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .failed)
        #expect(!fixture.operations.didSignalReady)
        #expect(try fixture.marker() == "old")
    }

    @Test func replacementFailureRollsBackOldApplication() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        fixture.operations.failReplacement = true
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .rolledBack)
        #expect(try fixture.marker() == "old")
        #expect(fixture.operations.launched == [fixture.target])
    }

    @Test func launchFailureRestoresOldApplicationAndReportsRollback() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        fixture.operations.failFirstLaunch = true
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .rolledBack)
        #expect(try fixture.marker() == "old")
        #expect(fixture.operations.launched == [fixture.target, fixture.target])
    }

    @Test func successfulInstallLaunchesNewApplicationAndRemovesBackup() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .installed)
        #expect(try fixture.marker() == "new")
        #expect(fixture.operations.didSignalReady)
        #expect(!FileManager.default.fileExists(atPath: fixture.backup.path))
        #expect(fixture.operations.launched == [fixture.target])
    }

    @Test func preexistingStageIsNeverDeletedByCleanup() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.plan.stageURL, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: fixture.plan.stageURL.appendingPathComponent("marker"))
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .failed)
        #expect(try String(contentsOf: fixture.plan.stageURL.appendingPathComponent("marker"), encoding: .utf8) == "keep")
        #expect(try fixture.marker() == "old")
    }

    @Test func candidateNestedSymlinkIsRejected() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        try FileManager.default.createSymbolicLink(at: fixture.plan.applicationURL.appendingPathComponent("escape"), withDestinationURL: fixture.root)
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .failed)
        #expect(!fixture.operations.didCopy)
        #expect(try fixture.marker() == "old")
    }

    @Test func kernelProcessIdentityIsStableAndHasMicrosecondPrecision() throws {
        let first = try InstallerSystem.parentIdentity(pid: ProcessInfo.processInfo.processIdentifier)
        let second = try InstallerSystem.parentIdentity(pid: ProcessInfo.processInfo.processIdentifier)
        #expect(first == second)
        #expect(first.startTime.split(separator: ".").count == 2)
        #expect(!first.executablePath.isEmpty)
    }

    @Test func rejectsEqualLowerAndMalformedVersions() throws {
        try InstallerSystem.requireUpgrade("1.14.2", from: "1.14.1")
        for version in ["1.14.1", "1.13.99", "1.14.2-beta", "1..2", "1.14", "1.14.2.1"] {
            #expect(throws: UpdateInstallationError.self) { try InstallerSystem.requireUpgrade(version, from: "1.14.1") }
        }
    }

    @Test func targetMutationDuringParentValidationCannotBecomeTrustedPin() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        fixture.operations.rewriteTargetOnParentValidation = true
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .failed)
        #expect(!fixture.operations.didSignalReady)
        #expect(!fixture.operations.didCopy)
        #expect(fixture.operations.launched.isEmpty)
    }
    @Test func sameInodeTargetRewriteIsDetectedBeforeReplacement() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        fixture.operations.rewriteTargetOnReady = true
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .failed)
        #expect(try fixture.marker() == "changed-in-place")
        #expect(!FileManager.default.fileExists(atPath: fixture.backup.path))
        #expect(fixture.operations.launched.isEmpty)
    }
    @Test func parentExitWithoutFinalCommitNeverReplacesApplication() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        fixture.operations.committed = false
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .cancelled)
        #expect(try fixture.marker() == "old")
        #expect(fixture.operations.launched.isEmpty)
    }

    @Test func explicitCancellationLeavesRunningApplicationUntouched() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        fixture.operations.cancelled = true
        let result = await UpdateInstallerEngine(operations: fixture.operations).run(fixture.plan)
        #expect(result.status == .cancelled)
        #expect(try fixture.marker() == "old")
        #expect(fixture.operations.launched.isEmpty)
    }
}

private struct InstallerFixture {
    let root: URL
    let workspace: URL
    let target: URL
    let plan: UpdateInstallationPlan
    let operations: FixtureInstallerOperations
    var backup: URL { plan.backupURL }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        workspace = root.appendingPathComponent("workspace")
        target = root.appendingPathComponent("Prism.app")
        let source = workspace.appendingPathComponent("Prism.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("marker"))
        try Data("new".utf8).write(to: source.appendingPathComponent("marker"))
        plan = UpdateInstallationPlan(id: UUID(), workspaceURL: workspace, applicationURL: source, targetURL: target, version: "1.14.2", parent: InstallerParentIdentity(pid: 123, startTime: "fixture", executablePath: target.appendingPathComponent("Contents/MacOS/Prism").path, userID: 501))
        operations = FixtureInstallerOperations()
    }
    func marker() throws -> String { try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class FixtureInstallerOperations: UpdateInstallerOperations, @unchecked Sendable {
    var didCopy = false
    var didSignalReady = false
    var parentStaysAlive = false
    var reusedPID = false
    var failCopy = false
    var failReplacement = false
    var failFirstLaunch = false
    var cancelled = false
    var committed = true
    var rewriteTargetOnReady = false
    var rewriteTargetOnParentValidation = false
    var launched: [URL] = []
    func validateApplication(_ url: URL, expectedVersion: String?) throws { }
    func validateParent(_ expected: InstallerParentIdentity, targetURL: URL) throws {
        guard expected.executablePath == targetURL.appendingPathComponent("Contents/MacOS/Prism").path else { throw UpdateInstallationError.parentMismatch }
        if rewriteTargetOnParentValidation { try Data("changed-during-attestation".utf8).write(to: targetURL.appendingPathComponent("marker")) }
    }
    func applicationFingerprint(_ url: URL) throws -> Data { try Data(contentsOf: url.appendingPathComponent("marker")) }
    func validateUpgrade(_ version: String, currentURL: URL) throws { }
    func parentState(_ expected: InstallerParentIdentity) -> InstallerParentState { reusedPID ? .reused : parentStaysAlive ? .running : .exited }
    func copyApplication(from: URL, to: URL) throws {
        didCopy = true
        if failCopy { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.copyItem(at: from, to: to)
    }
    func moveItem(from: URL, to: URL) throws {
        if failReplacement && from.lastPathComponent.hasPrefix(".Prism-update-") { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.moveItem(at: from, to: to)
    }
    func launch(_ url: URL) async throws {
        launched.append(url)
        if failFirstLaunch && launched.count == 1 { throw CocoaError(.executableLoad) }
    }
    func signalReady(_ plan: UpdateInstallationPlan) throws {
        didSignalReady = true
        if rewriteTargetOnReady { try Data("changed-in-place".utf8).write(to: plan.targetURL.appendingPathComponent("marker")) }
    }
    func isCancelled(_ plan: UpdateInstallationPlan) -> Bool { cancelled }
    func isCommitted(_ plan: UpdateInstallationPlan) -> Bool { committed }
    func writeReceipt(_ receipt: UpdateInstallationReceipt, plan: UpdateInstallationPlan) throws { }
}
