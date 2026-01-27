import { app, BrowserWindow } from 'electron';
import path from 'path';
import { createWindow, switchToDashboardMode, switchToPopupMode, registerWindowHandlers, getMainWindow, setIsPopupMode } from './windowManager.js';
import { createTray } from './trayManager.js';
import { registerIpcHandlers } from './ipcHandlers.js';
import { getSourceAppInfo } from './sourceAppInfo.js';

// 确保单实例
const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    switchToDashboardMode();
  });
}

// 注册为默认浏览器协议
if (process.defaultApp) {
  if (process.argv.length >= 2) {
    app.setAsDefaultProtocolClient('http', process.execPath, [path.resolve(process.argv[1])]);
    app.setAsDefaultProtocolClient('https', process.execPath, [path.resolve(process.argv[1])]);
  }
} else {
  app.setAsDefaultProtocolClient('http');
  app.setAsDefaultProtocolClient('https');
}

app.whenReady().then(() => {
  createWindow();
  createTray();
  registerWindowHandlers();
  registerIpcHandlers();
});

// 监听 macOS 点击 Dock 图标
app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  } else {
    switchToDashboardMode();
  }
});

// 确保应用在所有窗口关闭时退出
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

// 处理外部链接唤起
app.on('open-url', async (event, url) => {
  event.preventDefault();
  
  const { name: sourceApp, icon: sourceAppIcon, bundleId: sourceAppBundleId } = await getSourceAppInfo();
    
  console.log('Open URL event received:', { url, sourceApp, sourceAppBundleId });
    
  const mainWindow = getMainWindow();
  if (mainWindow) {
    switchToPopupMode(url, sourceApp, sourceAppIcon, sourceAppBundleId);
  } else {
    // Tell windowManager we are in popup mode so it doesn't default to dashboard
    setIsPopupMode(true);
    const win = createWindow();
    win.once('ready-to-show', () => {
      switchToPopupMode(url, sourceApp, sourceAppIcon, sourceAppBundleId);
    });
  }
});
