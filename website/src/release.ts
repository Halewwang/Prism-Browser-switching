// Keep the website on the native public-test release. GitHub's `latest` release
// still points to the older Electron channel and excludes prereleases.
export const release = {
  version: '1.14.0',
  build: '1',
  channel: 'Native Public Test',
  minimumSystem: 'macOS 15.0+',
  architecture: 'Universal · Apple Silicon + Intel',
  downloadUrl: 'https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.0/Prism-1.14.0-universal-test.dmg',
  notesUrl: 'https://github.com/Halewwang/Prism-Browser-switching/releases/tag/v1.14.0',
  checksumsUrl: 'https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.0/SHA256SUMS.txt',
  repositoryUrl: 'https://github.com/Halewwang/Prism-Browser-switching',
  issuesUrl: 'https://github.com/Halewwang/Prism-Browser-switching/issues',
} as const;
