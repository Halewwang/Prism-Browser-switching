# Prism 官网

官网介绍原生公开测试版，使用 React、TypeScript 与 Vite。发布版本、系统要求、架构与 GitHub 下载地址集中在 `src/release.ts`。

GitHub 的 `releases/latest` 排除预发布版本，目前仍指向旧 Electron 稳定版。官网必须使用原生公测的精确 tag 与 asset 地址。更新版本时同步 `src/release.ts`、根 README，以及发布说明；核对公开 release 的 prerelease 状态、架构、系统要求、安装包名称和校验值。

```bash
npm ci
npm run dev
npm run lint
npm run build
```

发布前还需在桌面和移动尺寸验证页面、下载链接、版本说明与截图。`public/app-screenshot-main.png` 和 `public/app-screenshot-popup.png` 来自原生应用；替换素材前确认不含私人链接或历史记录。

## 现有部署

官网地址为 https://prism-browser-switching.vercel.app（GitHub 仓库 homepage）。GitHub Deployments 记录显示现有 Vercel Git 集成为 PR 生成 Preview、为 main 合并生成 Production；无需新建平台或 GitHub Pages。2026-09-30 的主分支部署 `6748889715` 已成功，对应 SHA `98611b4`。

官网是独立的 `website/` Vite 项目；Vercel 项目应以 `website` 为 Root Directory，执行 `npm run build`，输出 `dist`，沿用 `website/vercel.json`。仓库根目录保留旧 Electron 页面。云端 Root Directory 无法仅由仓库文件证明，部署后需核对生产 HTML、下载 asset 与版本文案；根 `.vercel/project.json` 只有旧 projectName，不应据此新建或切换项目。发布公测时先上传精确 tag 的 DMG 和校验文件，再发布引用这些文件的官网。

当前截图为 v1.13.1 的公开素材，页面已标注示意；更新至 v1.14.0 真实截图前不能宣称截图展示全部新功能。
