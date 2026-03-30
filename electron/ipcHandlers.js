import { ipcMain, dialog, shell, app } from 'electron';
import { execFile } from 'child_process';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import pkg from '../package.json' assert { type: "json" };
import { scanInstalledBrowsers, saveCustomBrowser } from './browserScanner.js';
import { consumePendingDeepLinkPayload, getIsPopupMode, getMainWindow, setIsPopupMode } from './windowManager.js';

const ALLOWED_UPDATE_HOSTS = new Set([
  'github.com',
  'objects.githubusercontent.com',
  'raw.githubusercontent.com',
]);

const execFileAsync = (command, args = []) =>
  new Promise((resolve, reject) => {
    execFile(command, args, (error, stdout = '') => {
      if (error) {
        reject(error);
        return;
      }
      resolve(stdout);
    });
  });

const validateOpenUrl = (value) => {
  const parsed = new URL(value);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Unsupported URL protocol.');
  }
  return parsed;
};

const validateDownloadUrl = (downloadUrl) => {
  const parsed = new URL(downloadUrl);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    throw new Error('Unsupported update protocol.');
  }
  if (!ALLOWED_UPDATE_HOSTS.has(parsed.hostname)) {
    throw new Error('Unsupported update host.');
  }
  if (!parsed.pathname.toLowerCase().endsWith('.dmg')) {
    throw new Error('Update package must be a .dmg file.');
  }
  return parsed;
};

const validateSha256 = (value) => {
  if (!value) {
    return '';
  }

  const normalized = value.trim().toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(normalized)) {
    throw new Error('Invalid update checksum.');
  }
  return normalized;
};

const createSha256 = (filePath) => {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return hash.digest('hex');
};

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
       const stdout = await execFileAsync('mdls', ['-name', 'kMDItemCFBundleIdentifier', '-r', appPath]);
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

      validateOpenUrl(url);
      
      console.log('Opening URL in browser:', url, browserPath);
      execFile('open', ['-a', browserPath, url], (err) => {
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

  ipcMain.handle('get-view-mode', () => {
    return getIsPopupMode() ? 'popup' : 'dashboard';
  });

  ipcMain.handle('get-pending-deep-link', () => {
    return consumePendingDeepLinkPayload();
  });

  ipcMain.handle('start-download-update', async (_event, payload) => {
    const downloadUrl = typeof payload === 'string' ? payload : payload?.downloadUrl;
    const expectedFileName = typeof payload === 'object' ? payload?.fileName : undefined;
    const expectedSha256 = typeof payload === 'object' ? validateSha256(payload?.sha256) : '';

    if (!downloadUrl) {
      throw new Error('Missing update download URL.');
    }

    const parsed = validateDownloadUrl(downloadUrl);
    const mainWindow = getMainWindow();

    if (!mainWindow) {
      throw new Error('Main window is unavailable.');
    }

    const inferredFileName = decodeURIComponent(path.basename(parsed.pathname)) || `Prism-${pkg.version}.dmg`;
    const fileName = path.basename(expectedFileName || inferredFileName);

    if (!fileName.toLowerCase().endsWith('.dmg')) {
      throw new Error('Update filename must end with .dmg.');
    }

    const savePath = path.join(app.getPath('downloads'), fileName);

    return new Promise((resolve, reject) => {
      const ses = mainWindow.webContents.session;

      ses.once('will-download', (_downloadEvent, item) => {
        item.setSavePath(savePath);

        item.once('done', async (_event, state) => {
          if (state !== 'completed') {
            reject(new Error(`Download failed: ${state}`));
            return;
          }

          if (expectedSha256) {
            const actualSha256 = createSha256(savePath);
            if (actualSha256 !== expectedSha256) {
              fs.rmSync(savePath, { force: true });
              reject(new Error('Downloaded update failed checksum verification.'));
              return;
            }
          }

          const openError = await shell.openPath(savePath);
          if (openError) {
            shell.showItemInFolder(savePath);
          }

          resolve({ savePath, fileName, verified: !!expectedSha256 });
        });
      });

      try {
        mainWindow.webContents.downloadURL(downloadUrl);
      } catch (error) {
        reject(error);
      }
    });
  });
}
