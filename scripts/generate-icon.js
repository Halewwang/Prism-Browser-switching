import electron from 'electron';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const { app, BrowserWindow } = electron;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    show: false,
    width: 512,
    height: 512,
    webPreferences: {
      offscreen: true,
      backgroundThrottling: false,
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  const svgPath = path.join(__dirname, '../public/icon.svg');
  const svgContent = fs.readFileSync(svgPath, 'utf8');
  
  // Load SVG as data URI
  const html = `
    <html>
      <body style="margin: 0; padding: 0; overflow: hidden; background: transparent;">
        <img src="data:image/svg+xml;base64,${Buffer.from(svgContent).toString('base64')}" width="512" height="512" />
      </body>
    </html>
  `;
  
  await win.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);
  
  // Wait a bit for rendering
  setTimeout(async () => {
    try {
        const image = await win.webContents.capturePage();
        const pngBuffer = image.toPNG();
        
        if (!fs.existsSync(path.join(__dirname, '../build'))) {
            fs.mkdirSync(path.join(__dirname, '../build'));
        }
        
        fs.writeFileSync(path.join(__dirname, '../build/icon.png'), pngBuffer);
        console.log('Icon generated at build/icon.png');
    } catch (e) {
        console.error(e);
    }
    app.quit();
  }, 1000);
});