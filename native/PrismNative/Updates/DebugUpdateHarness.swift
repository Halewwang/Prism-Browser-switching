#if DEBUG
import Foundation

@MainActor enum DebugUpdateHarness {
    static func make() -> InAppUpdateWindowController {
        let base = URL(string: "https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.2/")!
        let installer = GitHubPublishedInstaller(version: "1.14.2", notes: "Prism 更新\n\n• 在应用内下载并校验更新\n• 确认后安装并重启\n• 安装失败时恢复原版本", downloadURL: base.appendingPathComponent("Prism-1.14.2-universal-test.dmg"), fileName: "Prism-1.14.2-universal-test.dmg")
        let model = InAppUpdateSession(
            installer: installer,
            prepare: { _, progress in
                for step in 0...20 { try await Task.sleep(for: .milliseconds(150)); progress(Double(step) / 20) }
                return PreparedUpdate(applicationURL: URL(fileURLWithPath: "/tmp/PrismUpdate-fixture/Prism.app"), workspaceURL: URL(fileURLWithPath: "/tmp/PrismUpdate-fixture"), installerFileURL: URL(fileURLWithPath: "/tmp/PrismUpdate-fixture/update.dmg"), version: "1.14.2")
            }, cleanup: { _ in }, startInstallation: { _ in {} },
            prepareTermination: { throw LinkIntakeService.UpdateTerminationError.pendingRequests },
            cancelTermination: {}, terminate: {}
        )
        return InAppUpdateWindowController(session: model)
    }
}
#endif
