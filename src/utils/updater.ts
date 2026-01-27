import { compare } from 'semver';

interface ReleaseData {
  version: string;
  notes: string;
  pub_date: string;
  url: string;
}

export interface UpdateInfo {
  hasUpdate: boolean;
  latestVersion: string;
  currentVersion: string;
  releaseDate: string;
  releaseNotes: string;
  downloadUrl: string;
  downloadSize: number;
}

// GitHub repository configuration
const REPO_OWNER = 'Halewwang';
const REPO_NAME = 'Prism-Browser-switching';
const BRANCH = 'main';

export const checkForUpdates = async (currentVersion: string): Promise<UpdateInfo> => {
  try {
    // Add timestamp to prevent caching
    const timestamp = new Date().getTime();
    // Use raw.githubusercontent.com to avoid API rate limits
    const url = `https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/latest-release.json?t=${timestamp}`;
    
    console.log('Checking for updates from:', url);
    
    const response = await fetch(url, {
      headers: {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache'
      }
    });
    
    if (!response.ok) {
      const statusText = response.statusText || 'Unknown Error';
      console.error(`Update Check Error: ${response.status} ${statusText}`);
      throw new Error(`Update Check Error: ${response.status} ${statusText}`);
    }

    const release: ReleaseData = await response.json();
    console.log('Latest release info:', release);
    
    // Normalize version strings (remove 'v' prefix if present)
    const latestVersion = release.version.replace(/^v/, '');
    const normalizedCurrentVersion = currentVersion.replace(/^v/, '');

    console.log(`Comparing versions: Current(${normalizedCurrentVersion}) vs Latest(${latestVersion})`);

    // Compare versions using semver
    const hasUpdate = compare(latestVersion, normalizedCurrentVersion) === 1;
    
    if (hasUpdate) {
        console.log('Update available!');
    } else {
        console.log('App is up to date.');
    }

    return {
      hasUpdate,
      latestVersion: release.version,
      currentVersion,
      releaseDate: release.pub_date,
      releaseNotes: release.notes,
      downloadUrl: release.url,
      downloadSize: 0 // We don't have size in the simple JSON, but it's fine
    };
  } catch (error) {
    console.error('Failed to check for updates:', error);
    throw error; // Propagate error to caller
  }
};
