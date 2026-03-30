import { ICON_ALIASES } from '../data/iconAliases';

const THESVG_BASE = 'https://cdn.jsdelivr.net/gh/GLINCKER/thesvg@main/public/icons';

export interface ResolveIconInput {
  appName?: string;
  bundleId?: string;
  type?: string;
  iconDataURL?: string;
}

export interface ResolveIconResult {
  kind: 'data-url' | 'thesvg' | 'fallback';
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

export const buildTheSvgUrl = (slug: string) => `${THESVG_BASE}/${slug}/default.svg`;

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
  if (slug) {
    return {
      kind: 'thesvg',
      src: buildTheSvgUrl(slug),
      letter,
    };
  }

  return {
    kind: 'fallback',
    letter,
  };
};
