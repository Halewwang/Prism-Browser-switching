import Foundation
import Testing
@testable import PrismNative

@Suite("In-app update workflow")
struct InAppUpdateSessionTests {
    @Test @MainActor func downloadOnlyPreparesAndExplicitInstallQuitsAfterHelperAndGate() async throws {
        var order: [String] = []
        let model = InAppUpdateSession(installer: fixtureInstaller(), prepare: { _, progress in
            order.append("download")
            progress(0.5)
            return fixturePrepared()
        }, cleanup: { _ in order.append("cleanup") }, startInstallation: { _ in
            order.append("helper-ready")
            return { order.append("cancel-helper") }
        }, prepareTermination: { order.append("durable-idle") }, cancelTermination: { order.append("resume") }, terminate: { order.append("quit") }, commitInstallation: { order.append("commit") })
        await model.download()
        #expect(model.stage == .ready)
        #expect(order == ["download"])
        await model.install()
        #expect(model.hasPreparedInstallation)
        #expect(order == ["download", "helper-ready", "durable-idle", "quit"])
        try model.commitPreparedInstallation()
        #expect(order.last == "commit")
        model.dispose()
        #expect(order.last == "commit")
    }

    @Test @MainActor func pendingLinksCancelHelperAndKeepPreparedPackageForRetry() async {
        var cancelled = 0
        var quit = false
        var cleaned = false
        let model = InAppUpdateSession(installer: fixtureInstaller(), prepare: { _, _ in fixturePrepared() }, cleanup: { _ in cleaned = true }, startInstallation: { _ in { cancelled += 1 } }, prepareTermination: { throw CocoaError(.userCancelled) }, cancelTermination: { }, terminate: { quit = true })
        await model.download()
        await model.install()
        #expect(!quit)
        #expect(cancelled == 1)
        #expect(!cleaned)
        #expect(!model.hasPreparedInstallation)
        #expect(model.stage == .ready)
        #expect(model.message != nil)
    }

    @Test @MainActor func downloadFailureCanRetryAndNeverStartsInstallation() async {
        var attempts = 0
        var installationCalls = 0
        let model = InAppUpdateSession(installer: fixtureInstaller(), prepare: { _, _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return fixturePrepared()
        }, cleanup: { _ in }, startInstallation: { _ in installationCalls += 1; return {} }, prepareTermination: {}, cancelTermination: {}, terminate: {})
        await model.download()
        #expect(model.stage == .failed)
        #expect(installationCalls == 0)
        await model.download()
        #expect(model.stage == .ready)
        #expect(attempts == 2)
    }

    @Test @MainActor func finalTerminationRejectionResumesApplicationAndCancelsHelper() async {
        var cancelled = 0
        var resumed = 0
        let model = InAppUpdateSession(installer: fixtureInstaller(), prepare: { _, _ in fixturePrepared() }, cleanup: { _ in }, startInstallation: { _ in { cancelled += 1 } }, prepareTermination: {}, cancelTermination: { resumed += 1 }, terminate: {})
        await model.download()
        await model.install()
        model.cancelPreparedInstallation(message: "A new link arrived")
        #expect(cancelled == 1)
        #expect(resumed == 1)
        #expect(model.stage == .ready)
        #expect(!model.hasPreparedInstallation)
    }

    private func fixtureInstaller() -> GitHubPublishedInstaller {
        GitHubPublishedInstaller(version: "1.14.2", notes: "Test release", downloadURL: URL(string: "https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.2/Prism-1.14.2-universal-test.dmg")!, fileName: "Prism-1.14.2-universal-test.dmg")
    }
    private func fixturePrepared() -> PreparedUpdate {
        PreparedUpdate(applicationURL: URL(fileURLWithPath: "/tmp/update-fixture/Prism.app"), workspaceURL: URL(fileURLWithPath: "/tmp/update-fixture"), installerFileURL: URL(fileURLWithPath: "/tmp/update-fixture/update.dmg"), version: "1.14.2")
    }
}
