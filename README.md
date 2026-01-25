# Prism for macOS

<div align="center">
  <img src="build/icon.png" alt="Prism Logo" width="128" height="128" />
  
  <h3>macOS 智能浏览器路由管家</h3>
  <p>接管系统链接点击，根据来源应用与规则，自动分发至最合适的浏览器。</p>

  <p>
    <a href="https://github.com/Halewwang/Prism-Browser-switching/releases">
      <img src="https://img.shields.io/github/v/release/Halewwang/Prism-Browser-switching?style=flat-square&color=000000" alt="Version" />
    </a>
    <a href="LICENSE">
      <img src="https://img.shields.io/github/license/Halewwang/Prism-Browser-switching?style=flat-square&color=000000" alt="License" />
    </a>
    <img src="https://img.shields.io/badge/platform-macOS-000000?style=flat-square&logo=apple" alt="Platform" />
  </p>
</div>

---

## 📖 项目概述 (Project Overview)

**Prism** 是一款专为 macOS 设计的高性能浏览器路由工具（Browser Router）。在现代工作流中，我们经常需要在多个浏览器之间切换：Chrome 用于开发调试，Arc 用于日常浏览，Safari 用于个人生活，或者 Edge 用于企业内网。

Prism 通过接管 macOS 的默认浏览器行为，充当了一个智能的“交通指挥官”。它能够精准识别点击链接的**来源应用程序**（如 Slack、钉钉、微信、飞书）以及 **URL 的特征**，并根据您预设的规则，自动将链接发送到最合适的浏览器中打开。

**核心价值：**
*   **工作生活分离**：自动将办公软件的链接分流至工作浏览器，社交软件链接分流至私人浏览器。
*   **开发效率提升**：特定内网或调试域名自动在开发版浏览器中打开。
*   **无感体验**：原生级的启动速度与 UI 设计，仿佛系统自带功能。

## ✨ 功能特性 (Features)

*   **🤖 智能来源识别**：采用底层系统调用，精准识别唤起链接的来源应用（支持微信、钉钉、飞书、Slack、Teams 等）。
*   **⚡️ 强大的规则引擎**：
    *   支持 **URL 关键字/正则** 匹配。
    *   支持按 **来源 App** 指定目标浏览器。
    *   支持 **优先级控制**（URL 规则 > 来源规则）。
*   **🎨 原生级 UI 体验**：遵循 macOS 设计规范，拥有精美的毛玻璃特效、圆角设计及原生应用图标显示。
*   **⌨️ 高效操作**：支持快捷键（数字键/方向键）快速选择浏览器，操作行云流水。
*   **📊 历史记录回溯**：自动记录跳转历史，方便随时查找错过的链接。
*   **🔒 隐私安全**：完全开源，所有数据仅存储在本地，绝不上传服务器。

## 🚀 快速开始 (Quick Start)

### 对于普通用户

1.  **下载**：访问 [Releases 页面](https://github.com/Halewwang/Prism-Browser-switching/releases) 下载最新的 `.dmg` 安装包。
2.  **安装**：打开 `.dmg` 文件，将 **Prism** 拖入 `Applications` 文件夹。
3.  **配置**：
    *   启动 Prism。
    *   前往 **系统设置** -> **桌面与程序坞** -> **默认浏览器**，选择 **Prism**。
    *   (可选) 在 Prism 设置中配置您的分发规则。

### 对于开发者

如果您想参与开发或自行构建，请确保您的环境满足以下要求：
*   **Node.js**: v18+
*   **macOS**: Intel 或 Apple Silicon

```bash
# 1. 克隆项目仓库
git clone https://github.com/Halewwang/Prism-Browser-switching.git
cd Prism-Browser-switching

# 2. 安装项目依赖
npm install

# 3. 启动开发环境
# 终端 A: 启动 React 前端服务
npm run dev

# 终端 B: 启动 Electron 主进程
npm start
```

## 💡 使用示例 (Usage Examples)

### 场景一：按来源应用分流

配置规则后，Prism 会自动处理链接跳转：

*   **规则**：来源应用 `DingTalk` (钉钉) -> 目标浏览器 `Chrome`
*   **效果**：在钉钉中点击的所有链接，都会自动在 Chrome 中打开，保持工作环境纯净。

### 场景二：按 URL 关键字分流

*   **规则**：URL 包含 `google.com` -> 目标浏览器 `Arc`
*   **规则**：URL 包含 `localhost:3000` -> 目标浏览器 `Firefox Developer Edition`
*   **效果**：访问特定域名或开发环境时，自动唤起对应的专用浏览器。

### 场景三：手动选择 (Selector)

当没有匹配任何规则时，Prism 会弹出一个轻量级选择框：

1.  点击链接。
2.  Prism 弹窗显示可用浏览器列表。
3.  按 `1` 选择 Chrome，按 `2` 选择 Safari（支持自定义快捷键）。

## ❓ 常见问题 (FAQ)

### ⚠️ 打开应用时提示 "Prism is damaged and can't be opened"？

这是由于 macOS 的安全机制（Gatekeeper）拦截了未签名的应用。由于本项目是开源免费项目，暂未购买 Apple 开发者证书进行签名。

**解决方法：**

请在终端（Terminal）中运行以下命令，即可正常打开：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Prism.app
```

### 🔒 为什么应用需要获取辅助功能权限？

Prism 需要使用辅助功能 API 来获取当前前台应用的窗口位置，以便将选择器弹窗精准显示在您的鼠标或窗口附近，提升使用体验。我们承诺不会读取您的任何其他敏感信息。

## 🤝 贡献指南 (Contributing)

我们非常欢迎社区贡献！如果您有好的想法或发现了 Bug，请按以下步骤操作：

1.  **Fork** 本仓库。
2.  创建一个新的分支 (`git checkout -b feature/AmazingFeature`)。
3.  提交您的更改 (`git commit -m 'Add some AmazingFeature'`)。
4.  推送到分支 (`git push origin feature/AmazingFeature`)。
5.  提交 **Pull Request**。

### 问题反馈
请在 [Issues](https://github.com/Halewwang/Prism-Browser-switching/issues) 页面提交 Bug 报告或功能请求。

## 📄 许可证 (License)

本项目基于 **MIT License** 开源。详情请参阅 [LICENSE](LICENSE) 文件。

---
<div align="center">
  Created with ❤️ by Hale
</div>
