# Prism for macOS 

<div align="center">
  <img src="build/icon.png" alt="Prism Logo" width="128" height="128" />
  <h3>您的 macOS 智能浏览器路由管家</h3>
  <p>接管系统链接点击，根据来源应用与规则，自动分发至最合适的浏览器。</p>
  <p>
    <a href="#-核心功能">核心功能</a> • 
    <a href="#-使用场景">使用场景</a> • 
    <a href="#-界面预览">界面预览</a> • 
    <a href="#-下载安装">下载安装</a>
  </p>
</div>

---

## 📖 项目简介

**Prism** 是一款专为 macOS 打造的高性能浏览器路由工具（Browser Router）。它旨在解决现代工作流中“多浏览器并存”带来的链接跳转痛点。

在日常工作中，我们往往需要同时使用多个浏览器：Chrome 用于开发调试，Arc 用于日常浏览，Safari 用于个人生活，或者 Edge 用于特定的企业内网应用。Prism 通过接管 macOS 的默认浏览器行为，充当了一个智能的“中间人”。它能够精准识别点击链接的**来源应用程序**（如 Slack、钉钉、微信、飞书）以及**URL 的特征**，并根据您预设的规则，自动将链接发送到最合适的浏览器中打开。

告别繁琐的手动复制粘贴，Prism 让每一次点击都精准抵达目的地。

## 🎯 目标用户

*   **全栈开发者**：需要在 Chrome/Firefox/Safari 之间频繁切换调试 Web 应用。
*   **企业白领/产品经理**：工作流依赖 Slack/钉钉/飞书等协作软件，需区分工作（Arc/Edge）与私人（Safari）浏览环境。
*   **多账号运营人员**：需要隔离不同浏览器的 Cookie 和会话环境。
*   **macOS 效率工具爱好者**：追求极致的原生体验与键盘操作效率。

## ✨ 核心功能与技术优势

*   **🤖 智能来源识别**
    *   采用底层系统调用 (`lsappinfo`)，精准识别唤起链接的来源应用（支持微信、钉钉、飞书、Slack、Teams 等），彻底解决传统工具识别不准的问题。
*   **⚡️ 强大的规则引擎**
    *   **URL 规则**：支持域名匹配、通配符匹配。
    *   **来源规则**：支持按“来源 App”指定目标浏览器。
    *   **优先级控制**：URL 规则优先于来源规则，灵活应对复杂场景。
*   **🎨 原生级 UI 体验**
    *   遵循 macOS Human Interface Guidelines 设计，拥有精美的毛玻璃特效与圆角设计。
    *   **无感唤起**：极速响应的弹窗选择器，支持键盘快捷键（数字键/方向键）快速选择。
    *   **原生图标**：直接提取系统已安装应用的官方高清图标，视觉体验如原生应用般统一。
*   **📊 历史记录回溯**
    *   自动记录每一次跳转的来源、目标及时间，方便随时回溯历史链接，不错过任何重要信息。
*   **🔒 隐私安全第一**
    *   完全开源，所有配置与历史数据仅存储在本地（LocalStorage/JSON），绝不上传任何服务器。

## 📸 界面预览

> *请在 `docs/images` 目录下添加以下截图以展示应用效果*

### 1. 智能选择弹窗 (Selector Popup)
当未匹配到规则或需要手动选择时，Prism 会弹出一个轻量级的选择框。支持键盘快捷键，操作行云流水。

![Selector Popup](docs/images/screenshot_popup.png)
*(建议替换为实际弹窗截图：展示来源应用图标、URL摘要及可用浏览器列表)*

### 2. 仪表盘与历史记录 (Dashboard)
清晰展示最近的跳转记录，精准显示来源应用（如钉钉、微信）与目标浏览器。

![Dashboard](docs/images/screenshot_dashboard.png)
*(建议替换为实际仪表盘截图：展示带有原生图标的历史记录列表)*

### 3. 规则配置 (Settings)
简单直观的规则管理界面，轻松添加 URL 或来源匹配规则。

![Settings](docs/images/screenshot_settings.png)
*(建议替换为实际设置页面截图)*

## 🚀 使用场景示例

*   **场景 A：工作与生活分离**
    *   配置规则：所有来自 **钉钉** 和 **飞书** 的链接 -> 自动在 **Chrome** (工作浏览器) 打开。
    *   配置规则：所有来自 **微信** 的链接 -> 自动在 **Safari** (生活浏览器) 打开。
*   **场景 B：特定内网开发**
    *   配置规则：当 URL 包含 `localhost` 或 `company-internal.com` -> 始终在 **Firefox Developer Edition** 打开。
*   **场景 C：视频会议**
    *   配置规则：当 URL 包含 `zoom.us` 或 `teams.microsoft.com` -> 自动在默认浏览器打开或提示选择，避免误触。

## 📥 下载安装

1.  访问 [Releases 页面](https://github.com/Halewwang/Prism-Browser-switching/releases) 下载最新的 `.dmg` 安装包。
2.  将 Prism 拖入 `Applications` 文件夹。
3.  启动 Prism，并按照提示在“系统设置 -> 桌面与程序坞 -> 默认浏览器”中选择 **Prism**。

## 🛠 开发与构建

如果您想参与开发或自行构建，请遵循以下步骤：

### 环境要求
*   Node.js (v18+)
*   macOS (Intel or Apple Silicon)

### 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/Halewwang/Prism-Browser-switching.git
cd Prism-Browser-switching

# 2. 安装依赖
npm install

# 3. 启动开发模式
# 终端 1: 启动 React 开发服务器
npm run dev

# 4. 启动 Electron 主进程 (在另一个终端)
npm start
```

### 构建发布包

```bash
# 执行自动化构建与打包
npm run dist
```
打包完成后，`.dmg` 安装文件将生成在 `release/` 目录下。

## 📝 技术栈

*   **Core**: [Electron](https://www.electronjs.org/) (Process Isolation, IPC)
*   **UI**: [React](https://reactjs.org/) + [TypeScript](https://www.typescriptlang.org/)
*   **Build**: [Vite](https://vitejs.dev/) + [Electron Builder](https://www.electron.build/)
*   **Styling**: [Tailwind CSS](https://tailwindcss.com/)
*   **System**: macOS AppleScript / `lsappinfo` integration

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 开源。

---
<div align="center">
  Created with ❤️ by Hale
</div>
