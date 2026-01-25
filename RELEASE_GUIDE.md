# 如何在 GitHub 发布应用更新 (Release)

目前的 `npm run sync` 命令仅负责同步**源代码**到 GitHub 仓库，它**不会**上传打包好的 `.dmg` 安装包。这是软件开发的标准最佳实践（Git 仓库只存代码，不存大文件）。

要让用户下载到安装包，您需要使用 GitHub 的 **Releases（发布）** 功能。

## 操作步骤

### 1. 找到安装包
在您的本地项目中，打包好的文件位于：
`release/Prism-1.2.5-arm64.dmg`

### 2. 在 GitHub 创建 Release
1.  打开您的 GitHub 仓库页面：[https://github.com/Halewwang/Prism-Browser-switching](https://github.com/Halewwang/Prism-Browser-switching)
2.  点击右侧边栏的 **"Releases"**。
3.  点击 **"Draft a new release"** 按钮。

### 3. 填写发布信息
*   **Choose a tag**: 输入版本号，例如 `v1.2.5`，点击 "Create new tag"。
*   **Release title**: 输入标题，例如 `v1.2.5 - UI 优化与图标更新`。
*   **Describe this release**: 可以在这里粘贴更新日志（见下文）。

### 4. 上传安装包
*   在底部的 **"Attach binaries by dropping them here..."** 区域。
*   将本地 `release/` 目录下的 `Prism-1.2.5-arm64.dmg` 文件拖进去。
*   等待上传进度条完成。

### 5. 发布
*   点击 **"Publish release"**。

---

## 推荐的更新日志 (Release Notes) 模板

您可以直接复制以下内容到 Release 描述中：

```markdown
## 🎉 新增功能与优化

### 🎨 UI/UX 全面升级
*   **全新图标**: 应用图标更新为 "Prism" 星号设计，状态栏图标同步更新。
*   **界面美化**: 移除了侧边栏黄色边框，优化了按钮悬停与点击效果。
*   **拖动优化**: 顶部增加全宽拖动区域，移动窗口更加自由。

### 📱 来源识别增强
*   新增对 **微信、钉钉、飞书、Slack、Teams、Telegram** 等常用办公软件的精准识别。
*   历史记录与弹窗现在会显示来源应用的**官方高清图标**。

### ⚡️ 核心逻辑重构
*   重构了路由规则引擎：**优先匹配 URL 规则**，其次匹配来源规则。
*   修复了在 Slack/钉钉 等应用中点击会议链接可能无法正确唤起 Zoom/Teams 的问题。

### 🛠 其他修复
*   修复了历史记录中图标显示不一致的问题。
*   优化了窗口阴影与圆角渲染。
```
