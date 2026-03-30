import { BrowserWindow, ipcMain, screen, app } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// 窗口尺寸常量
const DASHBOARD_SIZE = { width: 722, height: 520 };
const POPUP_SIZE = { width: 425, height: 200 };

let mainWindow = null;
let isPopupMode = false;

export function getMainWindow() {
    return mainWindow;
}

export function getIsPopupMode() {
    return isPopupMode;
}

export function setIsPopupMode(value) {
    isPopupMode = value;
}

export function createWindow() {
  mainWindow = new BrowserWindow({
    width: DASHBOARD_SIZE.width,
    height: DASHBOARD_SIZE.height,
    minWidth: 800,
    minHeight: 600,
    show: false,
    frame: false,
    transparent: true,
    resizable: true,
    hasShadow: false,
    backgroundColor: '#00000000',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      webSecurity: true
    },
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 34, y: 34 }
  });
  
  // Register window style update listener
  ipcMain.on('update-window-style', (event, isPopup) => {
    if (!mainWindow) return;
    if (isPopup) {
      mainWindow.setSize(POPUP_SIZE.width, POPUP_SIZE.height, true);
      mainWindow.setAlwaysOnTop(true, 'screen-saver');
      mainWindow.setSkipTaskbar(true);
      mainWindow.setResizable(false);
      if (process.platform === 'darwin') {
        mainWindow.setWindowButtonVisibility(false);
      }
    } else {
      mainWindow.setMinimumSize(800, 600);
      mainWindow.setSize(DASHBOARD_SIZE.width, DASHBOARD_SIZE.height, true);
      mainWindow.setAlwaysOnTop(false);
      mainWindow.setSkipTaskbar(false);
      mainWindow.setResizable(true);
      if (process.platform === 'darwin') {
        mainWindow.setWindowButtonVisibility(true);
      }
    }
  });

  const isDev = !app.isPackaged;
  if (isDev) {
    mainWindow.loadURL('http://localhost:5173');
  } else {
    mainWindow.loadFile(path.join(__dirname, '../dist/index.html'));
  }

  mainWindow.once('ready-to-show', () => {
    if (isPopupMode) {
      // If initialized in popup mode (handled by caller usually)
    } else {
      switchToDashboardMode();
    }
  });

  mainWindow.on('close', (e) => {
    if (!app.isQuitting && isPopupMode) {
      e.preventDefault();
      mainWindow.hide();
      isPopupMode = false;
      return false;
    }

    if (!app.isQuitting) {
      e.preventDefault();
      app.isQuitting = true;
      app.quit();
      return false;
    }
  });

  mainWindow.on('blur', () => {
    if (isPopupMode) {
      mainWindow.hide();
    }
  });
  
  return mainWindow;
}

export function switchToDashboardMode() {
  if (!mainWindow) return;
  isPopupMode = false;
  
  mainWindow.setResizable(true);
  mainWindow.setAlwaysOnTop(false);
  mainWindow.setSkipTaskbar(false);
  if (process.platform === 'darwin') {
    mainWindow.setWindowButtonVisibility(true);
  }
  
  mainWindow.setSize(DASHBOARD_SIZE.width, DASHBOARD_SIZE.height, true);
  mainWindow.center();
  mainWindow.show();
  mainWindow.focus();
  mainWindow.webContents.send('view-mode-change', 'dashboard');
}

export function switchToPopupMode(url, sourceApp, sourceAppIcon, sourceBundleId) {
  if (!mainWindow) return;
  isPopupMode = true;
  
  mainWindow.setSize(POPUP_SIZE.width, POPUP_SIZE.height, true);
  mainWindow.setAlwaysOnTop(true, 'screen-saver');
  mainWindow.setSkipTaskbar(true);
  mainWindow.setResizable(false);
  if (process.platform === 'darwin') {
    mainWindow.setWindowButtonVisibility(false);
  }
  
  // Calculate position (Follow Mouse)
  const cursorPoint = screen.getCursorScreenPoint();
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width: screenWidth, height: screenHeight } = primaryDisplay.workAreaSize;
  
  let x = cursorPoint.x;
  let y = cursorPoint.y;

  x = Math.round(x - (POPUP_SIZE.width / 2));
  y = Math.round(y + 10); 

  if (x < 0) x = 10;
  if (x + POPUP_SIZE.width > screenWidth) x = screenWidth - POPUP_SIZE.width - 10;
  if (y + POPUP_SIZE.height > screenHeight) {
      y = cursorPoint.y - POPUP_SIZE.height - 10;
  }
  if (y < 0) y = 10;

  mainWindow.setPosition(x, y);
  
  mainWindow.show();
  mainWindow.focus();
  
  mainWindow.webContents.send('view-mode-change', 'popup');
  setTimeout(() => {
    mainWindow.webContents.send('deep-link', { url, source: sourceApp, sourceIcon: sourceAppIcon, sourceBundleId });
  }, 100);
}

// Window control handlers helper
export function registerWindowHandlers() {
    ipcMain.on('close-window', () => {
        if (!mainWindow) return;
        if (isPopupMode) {
            mainWindow.hide();
            isPopupMode = false;
            return;
        }
        app.isQuitting = true;
        app.quit();
    });

    ipcMain.on('minimize-window', () => {
        if (mainWindow) mainWindow.minimize();
    });

    ipcMain.on('maximize-window', () => {
        if (mainWindow) {
            if (mainWindow.isMaximized()) {
            mainWindow.unmaximize();
            } else {
            mainWindow.maximize();
            }
        }
    });

    ipcMain.on('resize-me', (event, { width, height }) => {
        if(mainWindow) mainWindow.setSize(width, height);
    });
}
