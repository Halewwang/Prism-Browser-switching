# App 内完整更新 Implementation Plan

> **For agentic workers:** Use task ownership and red/green behavior checks; independent download and installer workflows run in parallel, root handles UI and lifecycle integration.

**Goal:** 下载、校验、用户确认、退出替换和重启全部通过原生应用完成，同时失败保留旧应用。

**Architecture:** GitHub release lookup 提供可信资产元数据；下载准备服务生成 PreparedUpdate；原生安装助手独立完成替换和回滚；主应用的更新窗口展示状态并只在明确确认和无处理中链接时退出。

**Tech Stack:** Swift 6 / SwiftUI / Foundation URLSession / CryptoKit SHA256 / Security / AppKit / XcodeGen。

## 工作流与所有权

- [ ] 下载服务：GitHubPublishedInstaller.swift、UpdatePackagePreparation.swift 和对应测试。先验证拒绝缺失/错误校验与非法来源，再实现元数据、下载、哈希、只读挂载及 app 准备。仅临时目录和公开包验证。
- [ ] 安装助手：UpdateInstallation.swift、新 helper target/共享实现、project.yml、打包验证脚本和对应测试。先验证目标逃逸、等待超时、复制/替换/重启失败回滚，再实现 handshake 和可恢复替换。不提升权限，不清除 quarantine。
- [ ] 根代理集成：GitHubUpdateChecker.swift、UpdateChecking.swift、更新窗口与状态模型、设置/生命周期、本地化。保留原检查行为，替换下载跳转；注入准备/安装依赖用于测试，确认后检查活动链接并启动助手，成功握手才退出。
- [ ] 验证与交付：受影响原生测试、PrismCore、隔离下载/签名/安装助手端到端、CUA 更新窗口、Universal 公测构建。记录自动及真实验证边界，产出可审查变更和候选包。旧 1.14.0 用户须手动更新一次。
