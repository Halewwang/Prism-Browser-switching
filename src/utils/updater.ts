import { compare } from 'semver';

interface GitHubRelease {
  tag_name: string;
  published_at: string;
  body: string;
  assets: Array<{
    name: string;
    browser_download_url: string;
    size: number;
  }>;
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

export const checkForUpdates = async (currentVersion: string): Promise<UpdateInfo> => {
  try {
    // Add timestamp to prevent caching
    const timestamp = new Date().getTime();
    const response = await fetch(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest?t=${timestamp}`, {
      headers: {
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache'
      }
    });
    
    if (!response.ok) {
      console.error(`GitHub API Error: ${response.status} ${response.statusText}`);
      throw new Error(`GitHub API Error: ${response.statusText}`);
    }

    const release: GitHubRelease = await response.json();
    console.log('Latest release info:', { tag: release.tag_name, published: release.published_at });
    
    // Normalize version strings (remove 'v' prefix if present)
    const latestVersion = release.tag_name.replace(/^v/, '');
    const normalizedCurrentVersion = currentVersion.replace(/^v/, '');

    console.log(`Comparing versions: Current(${normalizedCurrentVersion}) vs Latest(${latestVersion})`);

    // Compare versions using semver
    // Note: compare returns 1 if v1 > v2, 0 if v1 == v2, -1 if v1 < v2
    // We want to check if latestVersion > normalizedCurrentVersion
    const hasUpdate = compare(latestVersion, normalizedCurrentVersion) === 1;
    
    if (hasUpdate) {
        console.log('Update available!');
    } else {
        console.log('App is up to date.');
    }

    // Find the DMG asset for macOS
    const dmgAsset = release.assets.find(asset => asset.name.endsWith('.dmg') || asset.name.endsWith('-arm64.dmg'));
    const downloadUrl = dmgAsset ? dmgAsset.browser_download_url : '';
    const downloadSize = dmgAsset ? dmgAsset.size : 0;

    return {
      hasUpdate,
      latestVersion: release.tag_name,
      currentVersion,
      releaseDate: release.published_at,
      releaseNotes: release.body,
      downloadUrl,
      downloadSize
    };
  } catch (error) {
    console.error('Failed to check for updates:', error);
    // Return safe default on error
    return {
      hasUpdate: false,
      latestVersion: '',
      currentVersion,
      releaseDate: '',
      releaseNotes: '',
      downloadUrl: '',
      downloadSize: 0
    };
  }
};
