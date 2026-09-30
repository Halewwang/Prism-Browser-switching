// Keep the website on the native public-test release. GitHub's `latest` release
// still points to the older Electron channel and excludes prereleases.
export const release = {
  version: '1.14.1',
  build: '2',
  channel: 'Native Public Test',
  minimumSystem: 'macOS 15.0+',
  architecture: 'Universal · Apple Silicon + Intel',
  downloadUrl: 'https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.1/Prism-1.14.1-universal-test.dmg',
  notesUrl: 'https://github.com/Halewwang/Prism-Browser-switching/releases/tag/v1.14.1',
  checksumsUrl: 'https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.14.1/SHA256SUMS.txt',
  repositoryUrl: 'https://github.com/Halewwang/Prism-Browser-switching',
  issuesUrl: 'https://github.com/Halewwang/Prism-Browser-switching/issues',
} as const;
