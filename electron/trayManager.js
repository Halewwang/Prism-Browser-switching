import { Tray, Menu, nativeImage, app } from 'electron';
import path from 'path';
import { existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { getMainWindow, switchToDashboardMode, getIsPopupMode } from './windowManager.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let tray = null;

export function createTray() {
  const isPackaged = app.isPackaged;
  const trayIconPath = isPackaged 
      ? path.join(__dirname, '../dist/trayTemplate.png') 
      : path.join(__dirname, '../public/trayTemplate.png');
  
  let icon;
  
  if (existsSync(trayIconPath)) {
    icon = nativeImage.createFromPath(trayIconPath);
  } else {
    const pngPath = isPackaged 
        ? path.join(__dirname, '../dist/tray_icon.png')
        : path.join(__dirname, '../public/tray_icon.png');
        
    if (existsSync(pngPath)) {
        icon = nativeImage.createFromPath(pngPath).resize({ width: 22, height: 22 });
        icon.setTemplateImage(true);
    } else {
        icon = nativeImage.createFromDataURL('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAACXBIWXMAAAsTAAALEwEAmpwYAAAAWElEQVR4nO3XUQrAMAwF0K5g1i3FqJ0uT0I8e8Qr/ARkG0t+E+Fd03N7o1o8F3c2XQAAAABJRU5ErkJggg==');
    }
  }
  
  tray = new Tray(icon);
  tray.setToolTip('Prism');
  
  const contextMenu = Menu.buildFromTemplate([
    { label: 'Settings', click: () => switchToDashboardMode() },
    { label: 'Check for Updates', enabled: true, click: () => { 
        const mainWindow = getMainWindow();
        if (mainWindow) {
            switchToDashboardMode();
        }
    } },
    { type: 'separator' },
    { label: 'Quit Prism', click: () => {
        app.isQuitting = true;
        app.quit();
      } 
    }
  ]);
  
  tray.setContextMenu(contextMenu);

  tray.on('click', () => {
    if (getIsPopupMode()) return;
    
    const mainWindow = getMainWindow();
    if (mainWindow && mainWindow.isVisible()) {
      if (mainWindow.isFocused()) {
        mainWindow.hide();
      } else {
        mainWindow.show();
        mainWindow.focus();
      }
    } else {
      switchToDashboardMode();
    }
  });
}
