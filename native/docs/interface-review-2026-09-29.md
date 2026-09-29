# 界面审查与优化 · 2026-09-29

| Field | Value |
| --- | --- |
| Target | `working`，审查开始时的原生 macOS UI 改动 |
| Base ref | `HEAD` / `24eb116`；与 `origin/main` 的 merge-base 相同 |
| Head ref | `24eb116` 加工作区改动 |
| Commits | 0 committed；22 个已跟踪文件有改动，3 个新增文件未提交 |
| Files in scope | 24，包含新增共用控件和浏览器管理页 |
| Excluded | `DebugAppFixture.swift`：测试场景数据；生成输出、二进制、设计文件没有进入 diff |
| Surfaces expanded | 引导页、历史、规则、设置、浏览器管理共 5 个页面；共用侧栏、状态视图和恢复横幅本身已在改动范围内，无额外未改动消费者需要展开 |

实现是 SwiftUI + AppKit，沿用 Pen 的黑白灰颜色、固定桌面窗口和现有控件尺寸。依据项目的 `2026-08-12-prism-native-macos-design.md`、`pen-ui-redesign.md` 及用户提供的 AGENTS 指令。检查了 diff 的新增和移除部分，并读取新增文件。浏览器选择器按原设计保持独立，不在此次变更范围中；路由、持久化、安全及性能不属于本次界面审查。

用户同时要求优化，以下已直接实施。保留 668 × 554 引导页、1120 宽管理窗口、520 宽规则弹窗和原有字号层级，没有重新设计页面风格。

| Domain | Evidence inspected | Result |
| --- | --- | --- |
| Accessibility | 共用搜索与下拉框、规则菜单、历史条目、浏览器移除按钮的名称、值及键盘路径 | 修复历史元数据朗读和菜单上下文；补充清晰焦点边框；VoiceOver 实际朗读 Not verified |
| Layout | 5 个页面的分组、留白、操作区；中文短表单与英文来源应用长表单 | 修复历史筛选空间和长表单滚动；保留标题及稳定底部操作区 |
| Writing | 按钮实际动作、移除确认、完整变量模板及中英语言资源 | 确认消息显示目标名称与完整路径；新增模板均有中英翻译 |
| Typography | 标题/正文/说明层级、筛选标签、截断路径 | 修复英文标签截断和完整路径不可见问题；既定字号层级无其他可执行问题 |
| Colors | AppKit 在 Aqua / Dark Aqua 下解析的文字 RGBA；实际页面背景及颜色角色 | 原浅色次要文字最低 3.84:1；修复后浅色最低 4.99:1、深色最低 5.21:1 |
| UI | 共用控件的尺寸、边框、圆角、选中与禁用状态；页面及弹窗截图 | 无其他确认的表面/图标问题；长选项提供完整提示；慢速动画回放 Not verified |

以下严重程度描述修复前的影响；所有列出的修复均已实施。

| Severity | Domain | Status | Location | Before | After | Why |
| --- | --- | --- | --- | --- | --- | --- |
| HIGH | Typography | Introduced | `native/PrismNative/Features/Shell/BrowserManagementSheet.swift:146` | 路径固定单行省略，无完整值入口 | 完整路径悬停提示及文本选择 | 同名应用、失效路径需要完整目录才能辨认；保留紧凑行布局 |
| MEDIUM | Layout | Regression | `native/PrismNative/Features/Shell/RulesManagementView.swift:478` | 滚动 Form 被不滚动 VStack 替换 | 400 点以内保留短表单自然高度，超过后滚动；标题及 footer 在外 | 来源应用搜索、应用标识和保存错误会增加高度，需要稳定的保存/取消入口 |
| MEDIUM | Typography | Introduced | `native/PrismNative/Features/History/HistoryView.swift:150` | 5 个等宽筛选项内边距过大，英文 Processing 显示为 Processi… | 单项水平内边距 14 → 10，37/31 点高度不变 | 常用筛选项在正常窗口中应完整可读 |
| MEDIUM | Accessibility | Regression | `native/PrismNative/Features/History/HistoryRow.swift:33` | 普通朗读只有网址；来源、目标、结果在可关闭的 hint 中，时间丢失 | 普通标签包含安全网址、来源、目标、结果及事件时间；hint 只说明查看详情 | 恢复列表扫描所需信息，无需逐项进入详情 |
| MEDIUM | Accessibility | Introduced | `native/PrismNative/Features/Shell/RulesManagementView.swift:292` | 所有菜单名称都是 Rule actions | 完整本地化模板包含对应规则名称 | 辅助技术的控件列表需要区分操作目标 |
| MEDIUM | Writing | Introduced | `native/PrismNative/Features/Shell/BrowserManagementSheet.swift:135,162` | 多个 Remove 控件名称相同，确认没有目标名称/路径 | 控件名称含浏览器名称，确认显示名称和完整路径 | 执行移除前能核对目标，仍明确说明不会卸载应用 |
| MEDIUM | Accessibility | Introduced | `native/PrismNative/Features/Shell/WorkspaceControls.swift:88` | 下拉框关闭后焦点回到搜索框；键盘重新打开选项后 Esc 会连带关闭编辑弹窗 | 触发按钮可聚焦，支持空格、回车及 Esc；选项关闭后恢复原控件焦点 | 避免输入落到其他字段，或在关闭选项时误退出编辑 |
| MEDIUM | UI | Introduced | `native/PrismNative/Features/Shell/SettingsManagementView.swift:352` | 设置操作行的文字与箭头之间有不可点击的空白区，点击行中央无法打开浏览器管理 | 在按钮内容上加入整行矩形命中区域 | 操作行的可点击范围应与其视觉范围一致 |

已有问题，未归因于此次 Pen 改动，同样按用户要求修复：

| Severity | Domain | Location | Issue |
| --- | --- | --- | --- |
| HIGH | Colors | `native/PrismNative/Features/Shell/SystemSettingsChrome.swift:146` | 系统半透明次要文字在浅色背景上只有 3.84–3.95:1，低于普通文本 4.5:1；改为共用不透明语义颜色，浅色最小 4.99:1，深色最小 5.21:1 |
| MEDIUM | Writing | `native/PrismNative/Features/Onboarding/OnboardingView.swift:366` | 中文引导页的错误提示仍显示英文；补齐全部 8 种引导错误状态的标题及恢复说明，实际核对 HTTP/HTTPS 未完全接管时的中文渲染 |

此外，引导页 footer 的操作间距从 4 调整为 12，恢复长内容的滚动指示；搜索框清除按钮扩展到 24 × 24；输入框、搜索框和下拉框统一使用 2 点焦点边框，弹出选项关闭后恢复触发按钮的键盘焦点。

## 验证

- Debug UI-test build：`xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-UI -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/UIDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing`，通过。
- Universal Release：`xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Release -configuration Release -derivedDataPath build/UIReleaseData ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build`，通过；`lipo -archs` 确认同时包含 arm64 和 x86_64。
- 最终代码重新构建并执行单元测试，xcresult 汇总为 **384 项通过、0 失败、0 跳过**。
- **10 项不同的相关 UI 用例分批通过**：规则长表单与键盘焦点、规则取消、真实设置更新、历史浅/深色、缺失网址恢复、隐私、搜索详情、中文页面、无浏览器恢复，以及新增的设置操作行中央点击打开浏览器管理。首次回归发现的焦点、Esc 及操作行命中问题均修复后重跑；失败尝试没有计入通过数量。
- 本机 XCTest 窗口截图 API 在当前多显示器/屏幕共享环境报 `Image creation failed`。本轮显式启用 `PRISM_UI_CAPTURE_MODE=accessibility`，运行原生窗口尺寸、可访问性及交互断言，保存 AX 附件；默认的严格截图路径保留。**本轮没有执行自动图像亮度与明暗外观断言**，不将它们计为通过。
- 渲染核对改用电脑控制工具直接截图：中文欢迎、链接接管（包括已翻译的错误提示）、浏览器引导、历史空态、规则列表、短规则表单和设置；英文来源应用长表单及浏览器管理弹窗；深色历史列表。确认长表单保留保存/取消操作，焦点回到下拉框，英文 Processing 标签完整显示，浏览器列表和底部操作区无截断。
- 配色：读取 AppKit 解析的 sRGB RGBA，按实际不透明背景合成旧次要文字颜色，逐对计算 WCAG 相对亮度；检查 canvas、sidebar、group、iconWell 的浅/深色背景。数值针对文本实色，不以抗锯齿边缘作为前景。
- `plutil -lint`：中英语言资源通过；`git diff --check` 通过。
- Not verified：VoiceOver 实际朗读、伪本地化、RTL、放大文字、极短屏幕、浏览器管理页真实自定义长路径的悬停/移除交互、规则保存失败渲染，以及其余引导错误状态的中文渲染。普通窗口和安全 fixture 的交互已经覆盖，未将这些特殊场景算作通过。

## Verdict

Approve：在上述改动范围、正常窗口渲染与已完成的交互验证内，没有剩余的已确认 HIGH 问题。自动图像断言及列出的特殊场景保留为验证边界。

## v1.13.0 发布前复核

最终版本 1.13.0（构建 3）重新通过 384 项原生单元测试、81 项核心测试及 Universal Release 构建。版本化的中文引导和设置操作行自动 UI 用例通过；规则来源表单的 Esc → 空格用例自动失败，未计入通过数。诊断确认空格到达正确触发器并打开选项，随后 XCTest 路径中的应用前台切换使弹层关闭。

使用电脑控制工具在相同安全 fixture 中直接复核：Esc 后 AX 焦点为 Match，空格重新打开完整选项，方向键与回车将条件切换为 URL contains，保存和取消保持可见。此路径的实际交互通过，自动 XCTest 的前台切换仍是验证限制。原测试及断言完整保留；调试日志和无效的候选产品改动均已撤回。DEBUG 启动辅助窗口现在仅在真实主窗口尚未创建时使用，避免后续激活抢占焦点。
