
export interface BrowserApp {
  id: string;
  name: string;
  icon: string;
  path: string;
  isDefault?: boolean;
  bundleId?: string;
  type: 'chrome' | 'safari' | 'firefox' | 'arc' | 'edge' | 'brave' | 'vivaldi' | 'comet' | 'opera' | 'opera-gx' | 'chromium' | 'other';
  iconDataURL?: string;
}

export enum RuleType {
  SOURCE_APP = 'SOURCE_APP',
  URL_PATTERN = 'URL_PATTERN',
}

export interface RoutingRule {
  id: string;
  type: RuleType;
  value: string;
  targetBrowserId: string;
  description?: string;
  active: boolean;
  appName?: string; // Display name for SOURCE_APP rules
  appIcon?: string; // Base64 icon for SOURCE_APP rules
}

export interface HistoryLog {
  id: string;
  timestamp: Date;
  url: string;
  sourceApp?: string;
  sourceBundleId?: string;
  sourceAppIcon?: string;
  routedToBrowserId: string;
  method: 'Manual' | 'Rule' | 'AI' | 'Default';
}

export interface UpdateInfo {
  hasUpdate: boolean;
  latestVersion: string;
  downloadUrl: string;
}

export enum AppView {
  DASHBOARD = 'DASHBOARD',
  RULES = 'RULES',
  SETTINGS = 'SETTINGS',
  SIMULATION = 'SIMULATION'
}
