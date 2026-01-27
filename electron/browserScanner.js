import { app } from 'electron';
import { exec } from 'child_process';
import { existsSync, readFileSync, writeFileSync } from 'fs';
import path from 'path';

// 浏览器配置 (Bundle ID 映射)
const BROWSER_BUNDLE_IDS = {
  'b1': { name: 'Arc', bundleId: 'company.thebrowser.Browser', type: 'arc' },
  'b2': { name: 'Google Chrome', bundleId: 'com.google.Chrome', type: 'chrome' },
  'b3': { name: 'Safari', bundleId: 'com.apple.Safari', type: 'safari' },
  'b4': { name: 'Firefox', bundleId: 'org.mozilla.firefox', type: 'firefox' },
  'b5': { name: 'Microsoft Edge', bundleId: 'com.microsoft.edgemac', type: 'edge' },
  'b6': { name: 'Brave', bundleId: 'com.brave.Browser', type: 'brave' },
  'b7': { name: 'Vivaldi', bundleId: 'com.vivaldi.Vivaldi', type: 'vivaldi' },
  'b8': { name: 'Chrome Canary', bundleId: 'com.google.Chrome.canary', type: 'chrome' },
  'b9': { name: 'Comet', bundleId: 'com.comet.browser', type: 'comet' },
  'b10': { name: 'Opera', bundleId: 'com.operasoftware.Opera', type: 'opera' },
  'b11': { name: 'Opera GX', bundleId: 'com.operasoftware.OperaGX', type: 'opera-gx' },
  'b12': { name: 'Chromium', bundleId: 'org.chromium.Chromium', type: 'chromium' },
  'b13': { name: 'Firefox Developer Edition', bundleId: 'org.mozilla.firefoxdeveloperedition', type: 'firefox' },
  'b14': { name: 'Firefox Nightly', bundleId: 'org.mozilla.nightly', type: 'firefox' },
  'b15': { name: 'Edge Canary', bundleId: 'com.microsoft.edgemac.Canary', type: 'edge' },
  'b16': { name: 'Orion', bundleId: 'com.kagi.kagimacOS', type: 'other' },
  'b17': { name: 'SigmaOS', bundleId: 'com.sigmaos.sigmaos.macos', type: 'other' }
};

// 动态扫描已安装的应用程序（通用） - 仅保留浏览器扫描
async function scanAppsByBundleIds(bundleIdMap) {
  console.log('Scanning apps dynamically...');
  const installedApps = [];
  
  for (const [id, config] of Object.entries(bundleIdMap)) {
    try {
        const pathOutput = await new Promise((resolve) => {
            exec(`mdfind "kMDItemCFBundleIdentifier == '${config.bundleId}'" | head -n 1`, (err, stdout) => {
                resolve(stdout ? stdout.trim() : '');
            });
        });

        if (pathOutput && existsSync(pathOutput)) {
            console.log(`${config.name} found at ${pathOutput}`);
            let iconDataURL = '';
            try {
                const icon = await app.getFileIcon(pathOutput, { size: 'large' });
                iconDataURL = icon.toDataURL();
            } catch (err) {
                console.error(`Failed to get icon for ${config.name}:`, err);
            }

            installedApps.push({
                id: id,
                name: config.name,
                path: pathOutput,
                type: config.type || 'other',
                iconDataURL: iconDataURL,
                hasIcon: !!iconDataURL
            });
        }
    } catch (e) {
        console.error(`Error scanning for ${config.name}:`, e);
    }
  }
  return installedApps;
}

// Load Custom Browsers
export function getCustomBrowsers() {
  const userDataPath = app.getPath('userData');
  const customBrowsersPath = path.join(userDataPath, 'custom-browsers.json');
  if (existsSync(customBrowsersPath)) {
    try {
      const data = readFileSync(customBrowsersPath, 'utf-8');
      return JSON.parse(data);
    } catch (e) {
      console.error('Failed to load custom browsers', e);
      return [];
    }
  }
  return [];
}

export function saveCustomBrowser(browser) {
  const userDataPath = app.getPath('userData');
  const customBrowsersPath = path.join(userDataPath, 'custom-browsers.json');
  const browsers = getCustomBrowsers();
  
  // Check duplicates
  if (browsers.some(b => b.bundleId === browser.bundleId || b.path === browser.path)) {
    return false;
  }
  
  browsers.push(browser);
  try {
    writeFileSync(customBrowsersPath, JSON.stringify(browsers, null, 2));
    return true;
  } catch (e) {
    console.error('Failed to save custom browser', e);
    return false;
  }
}

// 扫描已安装的浏览器
export async function scanInstalledBrowsers() {
  const standardBrowsers = await scanAppsByBundleIds(BROWSER_BUNDLE_IDS);
  const customBrowsers = getCustomBrowsers();
  
  // Merge, prioritizing custom if duplicates (though unlikely due to ID differences)
  // Ensure custom browsers have necessary fields
  const formattedCustom = customBrowsers.map((b, index) => ({
      ...b,
      id: b.id || `custom-${Date.now()}-${index}`,
      type: b.type || 'other',
      hasIcon: !!b.iconDataURL
  }));
  
  return [...standardBrowsers, ...formattedCustom];
}
