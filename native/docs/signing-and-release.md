# Prism 原生版签名与发布

Developer ID 直发版本通过 Sparkle 和 HTTPS appcast 更新。公开测试版从 1.14.1 起使用独立原生更新助手，在 App 内下载、验证 Ed25519 更新签名与 SHA-256，用户确认后替换并重启。更新签名不等同于 Apple Developer ID 签名或公证。

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

## 公开测试版

公开测试版使用 `PrismNative-PublicTest` 独立构建目标，仅链接 PrismCore，使用 GitHub Releases 检查更新。正式 `PrismNative-Release` 目标保留 Sparkle。未配置 Developer ID 时，公开测试版保持硬化运行时与 ad hoc 签名，不链接 Sparkle，以免 macOS 在启动时因动态库签名校验拒绝加载。

```zsh
cd native
PRISM_UPDATE_SIGNING_KEY='/absolute/protected/path/update-ed25519.key' \
zsh scripts/package-public-test.sh 1.14.1 2
```

脚本生成 Universal DMG、SHA256SUMS.txt、update-manifest.json 和 update-manifest.sig。它分别签名内嵌 Universal 安装助手和外层应用，检查版本、双架构、签名、硬化运行时、无 Sparkle 动态依赖、DMG 完整性及隔离后的 5 秒进程启动。启动检查通过 `/usr/bin/sandbox-exec` 禁止子进程读取或写入当前账号的 `~/Library/Application Support/Prism` 整个目录（包括嵌套内容和目录解析后的路径）。该目录覆盖 `ModelContainerFactory` 的 `PrismNative.store` 及其备份、`AtomicPendingRequestStore` 的 `Recovery` 队列及备份，避免启动时恢复私人待处理链接或覆盖生产数据。脚本使用系统账号的真实主目录，不以临时 `HOME` 假装隔离；缺少可执行的 sandbox 工具时直接失败，绝不回退到普通启动。

更新私钥只保存于受保护的本机或 CI 密钥库，文件权限 0600、目录权限 0700，绝不提交到仓库。`scripts/sign-update.swift generate-key <path>` 仅用于首次生成，不覆盖已有密钥；已有客户端固定了 `PrismUpdateTrust` 公钥，后续发布必须沿用同一私钥。发布脚本会拒绝不匹配的密钥。建议独立备份私钥，丢失后已有客户端无法验证新包，需要手动安装迁移。

同一 GitHub Pre-release 必须上传上述四个资产。签名绑定版本、原生文件名、字节数、SHA-256、bundle ID 和最低系统版本。公开前重新下载全部资产，使用 `sign-update.swift verify <public-key> <manifest> <signature>` 验证签名，并核对实际 DMG 哈希。安装助手还会独立重验同一签名和 DMG，不信任此前解出的临时包。

1.14.0 及更早版本不包含安装助手，需要手动安装一次 1.14.1，之后才能使用完整 App 内更新。候选只在用户确认后安装，处理中或未保存的链接会阻止退出。无法写入目标目录或新版启动失败时保留／恢复旧应用。系统 Gatekeeper 检查仍生效：未公证版本可能需要手动允许；不删除 quarantine 或关闭安全检查。隔离安装验收与边界见 [update-installation-qa.md](update-installation-qa.md)。

这项 smoke 只检查动态依赖加载和进程能否保持运行，不证明生产持久化、来源识别、Profile 路由或完整实机操作。被 sandbox 拒绝的数据访问可能触发应用的临时存储降级；持久化和真实路由验收须在专用测试账号中另行完成。合成测试仅访问临时目录并验证隔离规则，不读取用户数据或启动 Prism：

```zsh
python3 scripts/test_smoke_public_test_launch.py
python3 scripts/smoke-public-test-launch.py /Applications/Prism.app
```

发布前还应在 `/Applications` 安装位置运行上述隔离启动检查，并从 GitHub 草稿重新下载文件核对哈希。不能只凭 `codesign --verify` 判断能否启动；v1.13.0 的嵌入式 Sparkle 曾通过静态签名检查，却被 macOS 运行时库校验拒绝。
