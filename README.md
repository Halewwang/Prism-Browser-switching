# Prism for macOS

<div align="center">
  <img src="website/public/app-icon.png" alt="Prism Logo" width="128" height="128" />
  <h3>链接，自有去处</h3>
  <p>原生 macOS 浏览器路由工具：按网址规则分流，按已确认的来源应用路由，或由你选择浏览器。</p>
  <p><strong>v1.14.2 · 构建 3 · 原生公开测试版</strong><br />macOS 15.0+ · Universal（Apple Silicon / Intel）</p>
  <p>
    <a href="https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.2/Prism-1.14.2-universal-test.dmg">下载原生公开测试版</a>
    · <a href="https://github.com/Halewwang/Prism-Browser-switching/releases/tag/v1.14.2">发布与安装说明</a>
  </p>
</div>

## 当前版本

当前推荐下载是 **v1.14.2 原生公开测试版**，采用 SwiftUI、AppKit 与 SwiftData，支持 macOS 15 或更新版本。一个 Universal 安装包同时包含 `arm64` 和 `x86_64`。

此测试版使用 **ad hoc 签名，尚未经过 Developer ID 签名和 Apple 公证**。macOS 可能阻止首次打开，需要你在确认下载来源后手动允许。该构建的签名和公证状态不等同于正式发行版。

请使用上方的精确版本下载链接。GitHub 的 `releases/latest` 目前仍指向旧 Electron 稳定版，不包含原生预发布版本；旧版与原生版的系统要求和功能范围不同。

## 功能与边界

- **网址规则**：支持精确域名、域名及其子域名、URL 包含文本三种匹配方式。
- **来源应用规则**：以应用标识匹配；仅当 macOS 提供的发送者信息被确认为 `confirmed` 时执行自动来源路由。不同应用的链接发送方式不同，不承诺识别所有应用或所有链接。
- **规则顺序**：先匹配网址规则，再匹配来源应用规则；同组内按你设置的顺序执行。可单独启停规则，也可暂停自动分流。
- **无匹配时的行为**：显示浏览器选择器、使用首选浏览器，或使用上次选择的浏览器。目标浏览器不可用时会回到选择器。
- **原生选择器**：靠近鼠标并限制在屏幕边界内，支持横向滚动、数字键、左右方向键、Return 确认与 Escape 取消。
- **浏览器管理**：发现本机浏览器，也可手动添加浏览器应用。支持隐藏和排序选择器中的选项；隐藏不影响规则和兜底目标。稳定版 Chrome／Edge 的 Profile 目标为实验功能。
- **规则预览与纠正**：输入网址并选择可选的模拟已确认来源，使用同一规则引擎预览命中结果，不打开浏览器；新建规则保存后可撤销。历史可跳转纠正当前规则，但不会把当前规则当作当时的完整快照。
- **本地记录**：规则、设置与链接历史保存在此 Mac，可在应用中查看和管理。

当前原生版**不支持正则表达式规则**。来源规则不会把当前前台应用的推测结果直接当作已确认的发送者。

**公测限制**：真实来源应用的覆盖仍不完整，不承诺所有应用都可识别。Chrome／Edge Profile 的冷启动、已运行浏览器中的指定 Profile、账号上下文及 Profile 删除场景尚未完成真实浏览器验收。Universal 包含 Intel 二进制，但尚未在 Intel 实机完成验收，也未覆盖所有受支持 macOS 版本。自动化测试不能替代这些实机结果，详见 [v1.14.2 公测说明](docs/public-test-release-1.14.2.md)。

## 安装与首次使用

1. 下载 [Prism-1.14.2-universal-test.dmg](https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.2/Prism-1.14.2-universal-test.dmg)。可同时下载 [SHA256SUMS.txt](https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.2/SHA256SUMS.txt)，在下载目录运行 `shasum -a 256 -c SHA256SUMS.txt` 核对文件完整性。
2. 退出已运行的 Prism，打开 DMG，将 Prism 拖入 `Applications`。更新时替换旧应用；设置和历史保存在应用包外。
3. **先尝试打开 Applications 中的 Prism**。若 macOS 提示无法验证开发者，在确认精确版本下载来源及校验值后，前往 **系统设置 → 隐私与安全性 → 仍要打开**，再在确认弹窗点击 **打开**。参见 [Apple 的首次打开说明](https://support.apple.com/en-us/102445)。不要将此步骤用于恶意软件或应用损坏警告。
4. 启动后按引导将 Prism 设为默认浏览器。也可前往 **系统设置 → 桌面与程序坞 → 默认网页浏览器** 选择 Prism。
5. 在设置中检查已发现的浏览器，选择没有匹配规则时的行为。
6. 在规则页添加网址规则或来源应用规则，然后从实际使用的应用打开 HTTP/HTTPS 链接进行验证。

此公开测试版尚未完成 Developer ID 签名和 Apple 公证；如果你不希望手动允许，请等待完成签名和公证的正式版本。受管理的 Mac 可能不允许更改安全设置。

## 使用示例

| 需求 | 规则 | 行为 |
| --- | --- | --- |
| 将 GitHub 链接用于工作 | 域名及子域名 `github.com` → Chrome | `github.com` 和 `docs.github.com` 都匹配 |
| 仅分流特定主机 | 精确域名 `example.com` → Safari | `www.example.com` 不匹配 |
| 分流开发地址 | URL 包含 `localhost:3000` → 开发浏览器 | 完整链接包含该文本时匹配 |
| 按来源分流 | 选择一个已安装的来源应用 → Chrome | 仅当发送者为 `confirmed` 且无更优先的网址规则时执行 |

没有匹配规则时，默认显示选择器。你可以直接点击浏览器，或按对应数字键；也可在设置中改为首选浏览器或上次使用的浏览器。

## 隐私与更新

链接路由在本机执行，规则和历史不上传到服务器。公开测试版通过 GitHub Releases 检查原生更新，自动检查可在设置中关闭。1.14.1 支持 App 内下载、进度、取消、重试和独立签名校验；确认后可尝试安装并重启，启动失败时恢复旧版。自动重启为测试能力，保留下载隔离标记的未公证新版在本机尚未完成启动验收，可能需要手动安装。1.14.0 及更早版本需手动安装一次 1.14.1 才能获得新更新能力。

Developer ID 正式版的 Sparkle 发布流程与公开测试版分开，参见 [原生签名与发布说明](native/docs/signing-and-release.md)。仓库根目录的 Electron 发布脚本和 `latest-release.json` 属于旧版发布流程，原生更新检查不使用该协议。

## 原生开发

**1.14.2 / Build 3 公测**修复管理窗口缩放时侧栏与页面内容被裁切的问题，窗口固定为 1120 × 800，设置仍可滚动。此前 **1.14.1 / Build 2 公测**增加 App 内下载、校验、安装确认和失败回滚；自动重启仍有上述限制。此前 **1.14.0 / Build 1 公测**增加实验性 Chrome／Edge Profile、新规则撤销、规则预览、历史解释及浏览器隐藏／排序。弹窗保持紧凑布局，创建规则仍可通过浏览器选项的右键菜单完成。实机验收要求见 [验收清单](native/docs/release-acceptance.md)，来源支持名单只接受真实证据。

原生代码位于 [`native/`](native)。需要 macOS 15+、支持 Swift 6 的 Xcode，以及 **XcodeGen 2.46.0**（生成脚本会检查精确版本）。

```bash
git clone https://github.com/Halewwang/Prism-Browser-switching.git
cd Prism-Browser-switching/native

# 运行独立路由核心测试
swift test

# 生成 Xcode 工程，再运行原生应用测试
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- test
```

在 Xcode 中打开生成的 `native/PrismNative.xcodeproj`，选择 `PrismNative-Unit` 开发与测试 scheme。公开测试构建使用 `PrismNative-PublicTest`，完整打包和核验步骤见 [发布说明](native/docs/signing-and-release.md)。

官网位于 [`website/`](website)，使用 React、TypeScript 与 Vite：

```bash
cd website
npm ci
npm run dev
# 提交前检查
npm run lint
npm run build
```

根目录的 `src/`、`electron/` 与 npm 开发命令保留旧 Electron 实现，不能用于构建上述原生公开测试版。

## 反馈与贡献

请在 [Issues](https://github.com/Halewwang/Prism-Browser-switching/issues) 中提交问题，附上 Prism 版本、macOS 版本、来源应用、期望行为和复现步骤。分享日志或截图前，请移除私人链接与历史内容。

欢迎通过 Pull Request 贡献。原生改动应运行相关核心与应用测试；官网改动应通过构建和 lint，并验证实际下载入口。
