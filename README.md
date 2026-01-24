# Prism for macOS

Prism 是一款专为 macOS 设计的智能浏览器路由工具。它能接管系统的默认浏览器行为，根据点击链接的**来源应用**或**URL 规则**，自动将链接分发到你指定的浏览器中打开。

告别在工作（Chrome/Arc）和生活（Safari）浏览器之间频繁手动复制粘贴的烦恼。

![Prism Icon](build/icon.png)

## ✨ 核心特性

*   **智能路由**：根据链接来源（如 Slack, 微信, 钉钉, Lark）自动选择目标浏览器。
*   **规则引擎**：支持按域名关键字或 URL 模式匹配，精准控制打开方式。
*   **无感唤起**：极速响应的弹窗选择器，支持键盘快捷键，提供原生 macOS 体验。
*   **历史记录**：自动记录所有跳转日志，方便回溯和管理。
*   **原生体验**：适配 macOS 深色/浅色模式，精美的 UI 设计，支持系统托盘管理。
*   **隐私安全**：所有配置和历史数据仅存储在本地，不上传任何服务器。

## 🚀 使用指南

1.  **下载安装**：下载并安装 Prism。
2.  **设为默认**：启动后，请在系统设置中将默认浏览器更改为 "Prism"。
3.  **配置规则**：
    *   打开 Prism 主界面（点击菜单栏图标或应用图标）。
    *   进入“路由规则”页面。
    *   添加规则：例如，“当链接来自 Slack 时，使用 Chrome 打开”或“当 URL 包含 `google.com` 时，使用 Arc 打开”。
4.  **开始使用**：在任何应用中点击链接，Prism 将自动根据您的规则进行跳转，或者弹出选择框供您手动选择。

## 🛠 开发指南

如果您想参与开发或自行构建，请遵循以下步骤：

### 环境要求
*   Node.js (v18+)
*   npm
*   macOS (Intel or Apple Silicon)

### 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/your-username/prism-macos.git
cd prism-macos

# 2. 安装依赖
npm install

# 3. 启动开发模式
# 终端 1: 启动 React 开发服务器
npm run dev

# 终端 2: 启动 Electron 主进程
# 注意：开发环境下建议使用无沙箱模式以避免权限问题
npx electron . --no-sandbox --user-data-dir=./dev-user-data
```

### 构建发布

```bash
# 1. 生成应用图标 (需先生成 assets)
npx electron scripts/generate-icon.js --no-sandbox

# 2. 打包 DMG 安装文件
npm run dist
```

打包完成后，`.dmg` 安装文件将生成在 `release/` 目录下。

## 📝 技术栈

*   **Core**: [Electron](https://www.electronjs.org/)
*   **UI**: [React](https://reactjs.org/) + [Vite](https://vitejs.dev/) + [TypeScript](https://www.typescriptlang.org/)
*   **Styling**: [Tailwind CSS](https://tailwindcss.com/)
*   **Design**: macOS Native-like UI (SF Pro 风格)

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 开源。

---
*Created by Hale*
