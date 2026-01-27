import { app } from 'electron';
import { exec } from 'child_process';
import { existsSync } from 'fs';

// Helper to get source app details
export async function getSourceAppInfo() {
  return new Promise((resolve) => {
    exec('lsappinfo visibleProcessList', async (error, stdout) => {
      let sourceAppName = 'Unknown';
      let sourceAppPath = '';
      let sourceAppIcon = '';
      let sourceAppBundleId = '';

      if (!error && stdout) {
        // Output format: ASN:0x...-"Name": ASN:0x...-"Name": ...
        const matches = stdout.match(/-"([^"]+)"/g);
        if (matches) {
          const appNames = matches.map(m => m.slice(2, -1)); // Remove -" and "
          // Filter out Prism itself and system apps
          const ignoreList = ['Prism', 'Electron', 'Finder', '访达', 'Dock', 'SystemUIServer', 'TRAE', 'Terminal', 'iTerm2', 'Xcode'];
          
          for (const name of appNames) {
             if (!ignoreList.includes(name)) {
                sourceAppName = name;
                break;
             }
          }
        }
      }

      if (sourceAppName !== 'Unknown') {
          try {
             const pathOutput = await new Promise((res) => {
                 exec(`lsappinfo info -only bundlepath "${sourceAppName}"`, (e, out) => res(out || ''));
             });
             const pathMatch = pathOutput.match(/"LSBundlePath"="([^"]+)"/);
             if (pathMatch) {
                 sourceAppPath = pathMatch[1];
             }
          } catch (e) {
              console.error('Failed to get app path', e);
          }

          if (sourceAppPath && existsSync(sourceAppPath)) {
              try {
                  const icon = await app.getFileIcon(sourceAppPath, { size: 'large' });
                  sourceAppIcon = icon.toDataURL();
              } catch (e) {
                  console.error('Failed to get app icon', e);
              }
              
              // Get Bundle ID
              try {
                 const stdout = await new Promise((res) => {
                     exec(`mdls -name kMDItemCFBundleIdentifier -r "${sourceAppPath}"`, (e, out) => res(out || ''));
                 });
                 if (stdout && stdout !== '(null)') {
                     sourceAppBundleId = stdout.trim();
                 }
              } catch (e) {
                 console.error('Failed to get app bundle id', e);
              }
          }
      }
      resolve({ name: sourceAppName, path: sourceAppPath, icon: sourceAppIcon, bundleId: sourceAppBundleId });
    });
  });
}
