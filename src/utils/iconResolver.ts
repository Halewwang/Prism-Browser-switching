import { ICON_ALIASES } from '../data/iconAliases';
import arcIcon from '../assets/browsers/arc.svg';
import chromeIcon from '../assets/browsers/chrome.svg';
import edgeIcon from '../assets/browsers/edge.svg';
import firefoxIcon from '../assets/browsers/firefox.svg';
import safariIcon from '../assets/browsers/safari.svg';

const LOCAL_ICON_ASSETS: Record<string, string> = {
  arc: arcIcon,
  'google-chrome': chromeIcon,
  safari: safariIcon,
  firefox: firefoxIcon,
  'microsoft-edge': edgeIcon,
};

export interface ResolveIconInput {
  appName?: string;
  bundleId?: string;
  type?: string;
  iconDataURL?: string;
}

export interface ResolveIconResult {
  kind: 'data-url' | 'local' | 'fallback';
  src?: string;
  letter: string;
}

const normalize = (value?: string) =>
  (value || '')
    .replace(/\.app$/i, '')
    .trim()
    .toLowerCase();

const getLetter = (value?: string) => {
  const normalized = (value || '').trim();
  return normalized ? normalized.charAt(0).toUpperCase() : '?';
};

export const resolveTheSvgSlug = ({ appName, bundleId, type }: ResolveIconInput): string | null => {
  const normalizedName = normalize(appName);
  const normalizedBundleId = normalize(bundleId);
  const normalizedType = normalize(type);

  const match = ICON_ALIASES.find((entry) => {
    if (normalizedBundleId && entry.bundleIds?.some((item) => normalize(item) === normalizedBundleId)) {
      return true;
    }
    if (normalizedType && entry.types?.some((item) => normalize(item) === normalizedType)) {
      return true;
    }
    if (normalizedName && entry.names?.some((item) => normalize(item) === normalizedName)) {
      return true;
    }
    return false;
  });

  return match?.slug || null;
};

export const resolveIcon = ({ appName, bundleId, type, iconDataURL }: ResolveIconInput): ResolveIconResult => {
  const letter = getLetter(appName || bundleId || type);

  if (iconDataURL) {
    return {
      kind: 'data-url',
      src: iconDataURL,
      letter,
    };
  }

  const slug = resolveTheSvgSlug({ appName, bundleId, type });
  const localAsset = slug ? LOCAL_ICON_ASSETS[slug] : undefined;

  if (localAsset) {
    return {
      kind: 'local',
      src: localAsset,
      letter,
    };
  }

  return {
    kind: 'fallback',
    letter,
  };
};
