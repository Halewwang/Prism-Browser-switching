# Prism 1.14.3 / Build 4 — 原生公开测试版

本版修复未公证公测更新被 macOS 阻止启动、随后恢复旧版的问题，增加用户明确授权的单次更新选项。

## 本次修复

- 下载并验证后，更新弹窗显示“允许安装此次未公证公测更新”，默认关闭，每次更新需要重新选择。
- 用户明确同意后，安装助手独立校验 Ed25519 签名、DMG 的 SHA-256、大小、版本和应用身份；通过原进程退出与最终安装确认后，仅移除暂存新版应用的下载隔离标记。
- 下载文件和原应用不受影响，不更改系统全局安全设置。
- 取消、启动身份验证和失败回滚继续有效。未勾选时保留隔离标记，未公证新版仍可能被系统阻止。
- 更新弹窗保持固定尺寸，中英文许可说明及安装按钮可正常访问。

## 安装与更新

macOS 15.0+；Universal（Apple Silicon / Intel），版本 1.14.3，构建 4。

**1.14.2 及更早版本需要先手动安装本版一次。** 旧版安装助手不含这项修复，无法通过下载新版获得安装当次所需的许可逻辑。退出 Prism，将 DMG 中的应用拖入 Applications 并替换旧版；规则、设置和历史保存在应用包外。

首次打开仍可能需要前往“系统设置 → 隐私与安全性 → 仍要打开”。参见 [Apple 说明](https://support.apple.com/zh-cn/102445)。本版继续使用 ad hoc 签名、硬化运行时及独立 Ed25519 更新签名，尚无 Developer ID 或 Apple 公证。

安装本版后，后续 App 内更新可在下载验证完成时选择本次公测许可，再点击“安装并重启”。未许可或受其他系统策略限制时仍可手动安装。

其他公测限制保持不变：Intel 实机、其他受支持 macOS、来源应用覆盖及 Chrome／Edge Profile 场景尚未全部完成验收，详见 [1.14.1 公测说明](public-test-release-1.14.1.md)。

## 验证

475 项原生 Swift 测试、7 项 XCTest 和 3 条更新 UI 流程测试通过。隔离标记与授权传递回归在修复前失败、修复后通过；UI 覆盖中文、英文、默认关闭、开启许可及安装按钮可点击。

Universal 双架构、应用与助手签名、隔离启动、DMG 只读挂载及更新清单验签通过，官网构建通过。

已用独立测试身份验证同一安装助手源码的真实更新：授权后，带隔离标记的新版在最终确认后替换旧包，经 LaunchServices 启动新进程并通过动态代码身份认证，回执为 installed；原 DMG 的隔离标记保留，备份清理与磁盘映像卸载通过。此项为 Apple Silicon 主机验证，不代表 Intel 实机验收。

六轮隔离安装助手检查通过：明确许可成功升级、缺省许可及 false 取消保留原包、DMG 篡改与签名篡改阻止替换、新版提前退出后恢复并启动旧版。QA 助手仅在仓库外编译时使用独立测试身份和公钥，产品身份及公钥保持不变。

同一版本提供 Prism-1.14.3-universal-test.dmg、SHA256SUMS.txt、update-manifest.json 和 update-manifest.sig。在下载目录执行 `shasum -a 256 -c SHA256SUMS.txt` 校验安装包。

安装包大小：4,618,790 bytes。

SHA-256：`f66c384efa9d7562cd23d325b3ee912b325a0824774b92cadddf36c189f3b1ff`。

[GitHub 发布说明](https://github.com/Halewwang/Prism-Browser-switching/releases/tag/v1.14.3) · [下载安装包](https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.3/Prism-1.14.3-universal-test.dmg)
