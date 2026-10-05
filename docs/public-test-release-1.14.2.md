# Prism 1.14.2 / Build 3 — 原生公开测试版

本版修复管理窗口缩小时，侧栏、标题和页面内容被裁切至不可见的问题。

## 本次修复

- 历史记录、规则和设置共用的管理窗口固定为 1120 × 800。
- 禁用手动缩放、缩放按钮和全屏入口，避免固定宽度布局被压缩。
- 设置页面仍可垂直滚动，底部更新与版本信息可正常访问。
- 引导窗口保持 668 × 554，完成引导后切换到管理窗口尺寸。

## 安装与更新

macOS 15.0+；Universal（Apple Silicon / Intel），版本 1.14.2，构建 3。

1.14.1 用户可在 App 内检查、下载和校验更新；安装重启仍为公测能力，未公证新版可能需要手动安装。1.14.0 及更早版本需要手动安装本版。下载 DMG 后退出 Prism，将应用拖入 Applications 并替换旧版；规则、设置和历史保存在应用包外。

继续沿用原生公测的 ad hoc 签名、硬化运行时和既有 Ed25519 更新签名，没有 Developer ID 签名或 Apple 公证。原有自动重启、Intel 实机、其他 macOS、来源应用和 Chrome／Edge Profile 验收限制保持不变，详见 [1.14.1 公测说明](public-test-release-1.14.1.md)。

## 验证

473 项原生 Swift 测试、7 项 XCTest、83 项核心测试、2 项 UI 流程检查及官网构建通过。窗口尺寸回归检查在修复前失败、修复后通过。已完成设置、规则、历史页面及引导流程检查，并实机验证拖拽不改变窗口尺寸、设置底部可滚动访问。UI 流程使用现有可访问性验证模式；显示结果由实机截图核对。

Universal 双架构、应用与更新助手签名、隔离启动、DMG 只读挂载和更新清单验签均通过。

同一版本提供四个文件：Prism-1.14.2-universal-test.dmg、SHA256SUMS.txt、update-manifest.json、update-manifest.sig。后两项供 App 内更新验签使用。在下载目录执行 `shasum -a 256 -c SHA256SUMS.txt` 校验安装包。

安装包大小：4,607,342 bytes。

SHA-256：`dc5486fdd27d80a651d1a821888cd4546cab92a2a33f251de4e19c3eedcc7360`。

[GitHub 发布说明](https://github.com/Halewwang/Prism-Browser-switching/releases/tag/v1.14.2) · [下载安装包](https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.2/Prism-1.14.2-universal-test.dmg)
