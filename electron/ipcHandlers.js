import { ipcMain, dialog, shell, app } from 'electron';
import { exec } from 'child_process';
import path from 'path';
import pkg from '../package.json' assert { type: "json" };
import { scanInstalledBrowsers, saveCustomBrowser } from './browserScanner.js';
import { getMainWindow, setIsPopupMode } from './windowManager.js';

export function registerIpcHandlers() {
  
  // 当渲染进程请求已安装浏览器列表时
  ipcMain.on('get-installed-browsers', async (event) => {
    const installedBrowsers = await scanInstalledBrowsers();
    event.reply('installed-browsers', installedBrowsers);
  });
  
  // 处理选择源应用请求
  ipcMain.handle('select-source-app', async () => {
    const mainWindow = getMainWindow();
    if (!mainWindow) return null;
    
    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ['openFile'],
      filters: [{ name: 'Applications', extensions: ['app'] }]
    });

    if (result.canceled || result.filePaths.length === 0) {
      return null;
    }

    const appPath = result.filePaths[0];
    const appName = path.basename(appPath, '.app');
    let iconDataURL = '';
    let bundleId = '';

    // Get Icon
    try {
      const icon = await app.getFileIcon(appPath, { size: 'large' });
      iconDataURL = icon.toDataURL();
    } catch (e) {
      console.error('Failed to get icon', e);
    }

    // Get Bundle ID
    try {
       const stdout = await new Promise((resolve) => {
           exec(`mdls -name kMDItemCFBundleIdentifier -r "${appPath}"`, (err, out) => resolve(out));
       });
       if (stdout && stdout !== '(null)') {
           bundleId = stdout.trim();
       }
    } catch (e) {
       console.error('Failed to get bundle id', e);
    }

    return {
      name: appName,
      path: appPath,
      iconDataURL,
      bundleId
    };
  });

  // Handle adding custom browser
  ipcMain.handle('add-custom-browser', async (event, browserData) => {
      console.log('Adding custom browser:', browserData);
      if (!browserData || !browserData.path) return null;
      
      const newId = `custom-${Date.now()}`;
      const saved = saveCustomBrowser({
          ...browserData,
          id: newId
      });
      
      if (saved) {
          // Refresh list for all windows
          const installedBrowsers = await scanInstalledBrowsers();
          const mainWindow = getMainWindow();
          if (mainWindow) {
             mainWindow.webContents.send('installed-browsers', installedBrowsers);
          }
          return newId;
      }
      return null;
  });

  ipcMain.on('open-in-browser', (event, { url, browserPath }) => {
    const mainWindow = getMainWindow();
    try {
      if (!url || !browserPath) {
        throw new Error('Missing required parameters: url or browserPath');
      }
      
      console.log('Opening URL in browser:', url, browserPath);
      const command = `open -a "${browserPath}" "${url}"`;
      
      exec(command, (err) => {
        if (err) {
          console.error('Failed to open URL in browser:', err);
          if (mainWindow) {
            mainWindow.webContents.send('open-in-browser-error', { 
              error: err.message, 
              url, 
              browserPath 
            });
          }
          return;
        }
        
        console.log('Successfully opened URL in browser');
        if (mainWindow) mainWindow.hide();
        setIsPopupMode(false);
      });
    } catch (error) {
      console.error('Error handling open-in-browser event:', error);
      if (mainWindow) {
        mainWindow.webContents.send('open-in-browser-error', { 
          error: error.message, 
          url, 
          browserPath 
        });
      }
    }
  });

  // Update Handlers
  ipcMain.handle('get-app-version', () => {
    return pkg.version;
  });

  ipcMain.on('start-download-update', (event, downloadUrl) => {
    shell.openExternal(downloadUrl);
  });
}
