# Prism v1.14.0 · Build 1 原生公开测试版

此版本作为 **GitHub Pre-release** 提供。需要 **macOS 15.0+**，Universal 安装包包含 Apple Silicon（arm64）和 Intel（x86_64）。

- [Prism-1.14.0-universal-test.dmg](https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.0/Prism-1.14.0-universal-test.dmg)
- [SHA256SUMS.txt](https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.0/SHA256SUMS.txt)
- [精确版本发布页](https://github.com/Halewwang/Prism-Browser-switching/releases/tag/v1.14.0)

请使用精确版本链接；GitHub 的 `releases/latest` 不包含预发布版本，可能指向旧 Electron 版。

## 本次变化

- 增加稳定版 Google Chrome／Microsoft Edge 的实验性 Profile 目标，可用于选择器和路由规则。
- 浏览器选项可隐藏、排序；隐藏只影响选择器，规则和兜底设置仍可使用这些目标。全隐藏时可从管理入口恢复。
- 规则编辑器展示范围与目标预览；保存新规则后可撤销。规则后来被修改时不会因旧撤销操作被删除，失败的撤销可以重试。
- 输入 HTTP/HTTPS 网址、选择可选的模拟已确认来源，预览实际规则引擎的匹配与目标，预览不会打开浏览器。
- 历史解释实际记录的打开方式及匹配规则 ID，并提供纠正当前规则的入口。历史没有保存完整规则快照；当前规则可能已经修改或删除。
- 来源状态、支持说明、错误提示和辅助功能标签更清晰；未知或推测来源不会自动执行来源规则。
- 选择器保持紧凑布局，创建规则仍可使用浏览器选项的右键菜单。

不支持正则表达式规则。URL 规则优先于已确认来源应用规则。

## 安装与首次打开

**此测试包使用 ad hoc 签名，未经过 Developer ID 签名或 Apple 公证。** 它的签名状态不等同于正式发行版。

1. 从上述发布页下载 DMG 和 `SHA256SUMS.txt`，将两者放在同一目录，运行 `shasum -a 256 -c SHA256SUMS.txt`。校验值用于检查文件完整性。
2. 退出 Prism，打开 DMG，将 Prism 拖入 Applications，更新时替换旧应用。
3. **先尝试打开 Applications 中的 Prism**。若 macOS 因无法验证开发者而阻止打开，在确认下载来源与校验结果后，进入 **系统设置 → 隐私与安全性 → 仍要打开**，在确认弹窗点击 **打开**。遵循 [Apple 的首次打开说明](https://support.apple.com/en-us/102445)，不要将此步骤用于恶意软件或应用损坏警告。受管理的 Mac 可能不允许更改安全设置。
4. 按引导设置默认浏览器，检查发现的浏览器和无匹配时的行为，再从日常应用测试链接。

如果不希望手动允许打开，请等待完成 Developer ID 签名和公证的正式版本。

## 公开测试限制

自动化测试和构建检查通过，不代表已完成所有实机验收。

- **真实来源覆盖不足**：来源路由仅在单条链接的发送者被确认为 `confirmed` 时执行。不同应用发送链接的方式不同；真实应用的冷启动、已运行状态及重复链接覆盖仍不完整，不承诺支持所有应用或所有链接。
- **Profile 为实验功能**：Chrome／Edge 的真实冷启动、浏览器已经运行时指定 Profile、账号上下文和 Profile 被删除后的处理，尚未完成真实浏览器验收。其他浏览器暂不提供 Profile 发现与路由。
- **Intel 与系统版本覆盖不足**：已构建 Universal 二进制，但未在物理 Intel Mac 上完成验收，也未覆盖所有受支持的 macOS 版本。
- **规则历史不是快照**：历史只记录匹配规则 ID 等结果，不能从当前规则还原当时的全部条件。

实机矩阵和验证要求见 [原生验收清单](https://github.com/Halewwang/Prism-Browser-switching/blob/v1.14.0/native/docs/release-acceptance.md)。反馈请附版本、macOS、Mac 架构、来源应用、目标浏览器／Profile、启动状态和复现步骤；分享前删除私人链接和账号信息。

## English

Prism v1.14.0, build 1 is a native **public test / GitHub Pre-release** for macOS 15+. The Universal DMG includes Apple Silicon and Intel binaries. It uses **ad hoc signing without Developer ID signing or Apple notarization**.

Verify the DMG with the accompanying SHA256SUMS.txt, drag Prism into Applications, and **try opening it first**. If macOS blocks the trusted download because it cannot verify the developer, use System Settings → Privacy & Security → Open Anyway, then confirm Open. Follow [Apple’s guidance](https://support.apple.com/en-us/102445); this procedure does not apply to malware or damaged-app warnings.

This release adds experimental stable Chrome/Edge profile targets, selector visibility/order, rule preview, new-rule undo, and history correction. Real-app source attribution, real-browser profile/account behavior, physical Intel hardware, and all supported macOS versions are not fully verified. Source rules require a confirmed sender for the individual link. Automated tests do not establish complete real-world compatibility.
