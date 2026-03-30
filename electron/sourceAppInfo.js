import { app } from 'electron';
import { execFile } from 'child_process';
import { existsSync } from 'fs';

const IGNORE_APPS = new Set([
  'Prism',
  'Electron',
  'Finder',
  '访达',
  'Dock',
  'SystemUIServer',
  'TRAE',
  'Terminal',
  'iTerm2',
  'Xcode',
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

const isIgnoredApp = (name = '') => IGNORE_APPS.has(name.trim());

const parseVisibleProcessList = (stdout = '') => {
  const matches = stdout.match(/-"([^"]+)"/g);
  if (!matches) {
    return [];
  }

  return matches
    .map((match) => match.slice(2, -1).trim())
    .filter(Boolean);
};

const getFrontmostAppInfo = async () => {
  try {
    const script = `
      tell application "System Events"
        set frontApp to first application process whose frontmost is true
        set appName to name of frontApp
        set appBundleId to bundle identifier of frontApp
        return appName & "||" & appBundleId
      end tell
    `;
    const stdout = await execFileAsync('osascript', ['-e', script]);
    const [name = '', bundleId = ''] = stdout.trim().split('||');
    return { name: name.trim(), bundleId: bundleId.trim() };
  } catch (error) {
    console.error('Failed to get frontmost app', error);
    return { name: '', bundleId: '' };
  }
};

const getAppDetails = async (appName, knownBundleId = '') => {
  let sourceAppPath = '';
  let sourceAppIcon = '';
  let sourceAppBundleId = knownBundleId;

  try {
    const pathOutput = await execFileAsync('lsappinfo', ['info', '-only', 'bundlepath', appName]);
    const pathMatch = pathOutput.match(/"LSBundlePath"="([^"]+)"/);
    if (pathMatch) {
      sourceAppPath = pathMatch[1];
    }
  } catch (error) {
    console.error('Failed to get app path', error);
  }

  if (!sourceAppPath || !existsSync(sourceAppPath)) {
    return { name: appName, path: '', icon: '', bundleId: sourceAppBundleId };
  }

  try {
    const icon = await app.getFileIcon(sourceAppPath, { size: 'large' });
    sourceAppIcon = icon.toDataURL();
  } catch (error) {
    console.error('Failed to get app icon', error);
  }

  if (!sourceAppBundleId) {
    try {
      const bundleOutput = await execFileAsync('mdls', ['-name', 'kMDItemCFBundleIdentifier', '-r', sourceAppPath]);
      if (bundleOutput && bundleOutput !== '(null)') {
        sourceAppBundleId = bundleOutput.trim();
      }
    } catch (error) {
      console.error('Failed to get app bundle id', error);
    }
  }

  return { name: appName, path: sourceAppPath, icon: sourceAppIcon, bundleId: sourceAppBundleId };
};

// Helper to get source app details
export async function getSourceAppInfo() {
  try {
    const frontmostApp = await getFrontmostAppInfo();
    if (frontmostApp.name && !isIgnoredApp(frontmostApp.name)) {
      const details = await getAppDetails(frontmostApp.name, frontmostApp.bundleId);
      if (details.path || details.bundleId) {
        return details;
      }
    }

    const stdout = await execFileAsync('lsappinfo', ['visibleProcessList']);
    const appNames = parseVisibleProcessList(stdout);
    const candidateName = appNames.find((name) => !isIgnoredApp(name));

    if (!candidateName) {
      return { name: 'Unknown', path: '', icon: '', bundleId: '' };
    }

    return await getAppDetails(candidateName);
  } catch (error) {
    console.error('Failed to resolve source app info', error);
    return { name: 'Unknown', path: '', icon: '', bundleId: '' };
  }
}
