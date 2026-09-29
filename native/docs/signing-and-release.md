# Prism 原生版签名与发布

此流程只面向 Developer ID 直发版本。带有有效 EdDSA 公钥和 HTTPS appcast 的构建通过 Sparkle 检查并安装签名更新；未配置公钥的构建通过 GitHub Releases 检查原生安装包，用户确认下载后手动替换 Applications 中的 Prism。

GitHub 检查包含原生公开测试预发布版本，从 `1.11.0` 起仅识别 `Prism-<version>-universal-test.dmg` 与本流程生成的 `Prism-<version>.dmg`，不使用旧 Electron 的 `latest-release.json`。自动检查开关与 Sparkle 共用 `SUEnableAutomaticChecks` 偏好：启动后检查，之后每天检查，同一新版本只自动提示一次；手动检查始终反馈最新、可用更新或错误。

## 发布前提

发布操作者需要在本机钥匙串或 CI 密钥库中配置以下值，任何私钥都不得写入仓库：

- `DEVELOPER_ID_APPLICATION`：Developer ID Application 证书名称。
- `DEVELOPMENT_TEAM`：Apple Team ID。
- `NOTARY_PROFILE`：已由 `notarytool store-credentials` 保存的钥匙串 profile。
- `SPARKLE_PUBLIC_ED_KEY`：Sparkle EdDSA 公钥。
- `SPARKLE_ED_PRIVATE_KEY`：Sparkle EdDSA 私钥，仅通过标准输入提供给 `generate_appcast`。
- `SPARKLE_TOOLS_ROOT`：包含 `bin/generate_appcast` 的已验证 Sparkle 工具目录。

## 生成与核验

```zsh
cd native
SPARKLE_PUBLIC_ED_KEY='…' \
SPARKLE_ED_PRIVATE_KEY='…' \
SPARKLE_TOOLS_ROOT='/absolute/path/to/sparkle-tools' \
DEVELOPER_ID_APPLICATION='Developer ID Application: …' \
DEVELOPMENT_TEAM='…' \
NOTARY_PROFILE='prism-notary' \
zsh scripts/package-release.sh 1.0.0 1
```

脚本会：运行原生测试、归档通用二进制、Developer ID 导出、提交并装订应用与 DMG、验证架构/版本/签名/硬化运行时/Gatekeeper/装订状态，并在所有验证完成后才生成 appcast。输出目录为 `native/build/release/<version>-<build>/`，已有目录会拒绝覆盖。

可单独验证已有工件：

```zsh
zsh scripts/verify-release.sh /absolute/path/Prism.app 1.0.0 1 /absolute/path/Prism-1.0.0.dmg
```

在 GitHub 发布为公开状态前，应将经过验证的 DMG 与 appcast 作为同一个草稿发布的资产上传，随后重新下载资产复核字节大小、签名和 appcast 签名；确认后再发布草稿。这样失败不会覆盖已公开的更新源。
