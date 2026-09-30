# Prism 1.14.1 / Build 2 — 原生公开测试版

本版增加 App 内下载和校验，以及安装确认、失败回滚。**自动重启为测试能力，尚未通过完整实机验收。** 未公证新版可能被 macOS 拦截并回滚，需要手动安装。

## 本次更新

- 新版提示直接打开更新窗口，提供下载进度、取消、重试和发布说明。
- 固定 Ed25519 公钥验证更新清单，核验实际文件大小、SHA-256、应用身份、版本、系统要求和代码签名。
- 验证通过后才提供“安装并重启”，下载完成不会自动安装。
- 安装前保存链接状态；待处理或未保存链接会阻止退出。独立助手重新验包，启动失败恢复旧版。

## 安装与迁移

macOS 15.0+；Universal（Apple Silicon / Intel），版本 1.14.1，构建 2。

**1.14.0 及更早版本需手动安装一次本版**，才能获得 App 内下载与校验。下载 DMG 后退出 Prism，将应用拖入 Applications 并替换旧版。规则、设置和历史保存在应用包外。

本版继续使用 ad hoc 签名与硬化运行时，**没有 Developer ID 签名和 Apple 公证**。更新包的 Ed25519 签名验证发布内容，不等同于 Apple 身份认证。保留下载隔离标记和系统安全检查。首次启动如提示无法验证开发者，请确认来源和校验值后，按 macOS 的“系统设置 → 隐私与安全性 → 仍要打开”流程操作。

## 验证与限制

472 项原生 Swift 测试、7 项 XCTest、83 项核心测试、2 项更新 UI 测试、3 项签名脚本测试通过；实际 GitHub 下载、安装取消、启动失败回滚已验证。Universal 包、应用及助手签名、只读挂载与更新清单验签通过。

在本机 macOS 27.2 / arm64，保留下载隔离标记的未公证新版未完成启动，助手正确恢复旧版。因此不承诺无干预的自动重启。Intel 实机、其他 macOS、来源应用及 Chrome／Edge Profile 的完整验收仍未完成。

## 下载与校验

同一版本提供四个文件：DMG、SHA256SUMS.txt、update-manifest.json、update-manifest.sig。后两项供 App 内更新验签使用。

DMG 大小：4,606,405 bytes。

SHA-256：`4000f84166720c0276e259c90cbfa0441a7042cf543a3454432fa88135bfb9d1`

在下载目录执行 `shasum -a 256 -c SHA256SUMS.txt` 验证安装包。

[GitHub 发布说明](https://github.com/Halewwang/Prism-Browser-switching/releases/tag/v1.14.1) · [下载安装包](https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.1/Prism-1.14.1-universal-test.dmg)

详细工程验证见 [完整更新交付记录](in-app-update-delivery-2026-09-30.md)。
