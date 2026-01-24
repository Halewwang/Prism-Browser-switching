# LinkMaster macOS Router - 新设备配置指南

欢迎回到 LinkMaster 开发！在新电脑上开始工作，请遵循以下步骤：

## 1. 获取代码
打开终端，运行以下命令将代码下载到本地：
```bash
git clone https://github.com/AdlerMurcus/LinkMaster-macOS-Router.git
cd LinkMaster-macOS-Router
```

## 2. 安装依赖
确保你的新电脑上已安装 Node.js，然后运行：
```bash
npm install
```

## 3. 启动开发环境
你需要开启两个终端窗口来分别运行前端和主进程：

**终端 1 (启动 React 前端):**
```bash
npm run dev
```

**终端 2 (启动 Electron 应用):**
```bash
npm start
```

## 4. 同步更改
- **获取最新代码**: `git pull`
- **提交你的更改**: `git add .` -> `git commit -m "你的描述"` -> `git push`
