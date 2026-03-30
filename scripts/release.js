import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { execFileSync, spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import readline from 'readline';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.join(__dirname, '..');
const PACKAGE_JSON_PATH = path.join(ROOT_DIR, 'package.json');
const PACKAGE_LOCK_PATH = path.join(ROOT_DIR, 'package-lock.json');
const RELEASE_NOTES_PATH = path.join(ROOT_DIR, 'RELEASE_NOTES.md');
const LATEST_RELEASE_PATH = path.join(ROOT_DIR, 'latest-release.json');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

const askQuestion = (query) => new Promise((resolve) => rl.question(query, resolve));

const run = (command, args = []) => {
  console.log(`running: ${[command, ...args].join(' ')}`);
  const result = spawnSync(command, args, {
    cwd: ROOT_DIR,
    stdio: 'inherit',
  });

  if (result.status !== 0) {
    console.error(`❌ Command failed: ${command}`);
    process.exit(result.status || 1);
  }
};

const readJson = (filePath) => JSON.parse(fs.readFileSync(filePath, 'utf8'));

const writeJson = (filePath, data) => {
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`);
};

const getGitLogs = () => {
  try {
    const lastTag = execFileSync('git', ['describe', '--tags', '--abbrev=0'], {
      cwd: ROOT_DIR,
      encoding: 'utf8',
    }).trim();
    const logs = execFileSync('git', ['log', `${lastTag}..HEAD`, '--pretty=format:* %s (%h)'], {
      cwd: ROOT_DIR,
      encoding: 'utf8',
    });
    return { lastTag, logs };
  } catch (_error) {
    const logs = execFileSync('git', ['log', '--pretty=format:* %s (%h)', '-n', '10'], {
      cwd: ROOT_DIR,
      encoding: 'utf8',
    });
    return { lastTag: 'v0.0.0', logs };
  }
};

const updateVersion = (type) => {
  const pkg = readJson(PACKAGE_JSON_PATH);
  const lock = fs.existsSync(PACKAGE_LOCK_PATH) ? readJson(PACKAGE_LOCK_PATH) : null;

  const oldVersion = pkg.version;
  let [major, minor, patch] = oldVersion.split('.').map(Number);

  if (type === 'major') major++;
  else if (type === 'minor') minor++;
  else patch++;

  if (type === 'major') {
    minor = 0;
    patch = 0;
  }
  if (type === 'minor') {
    patch = 0;
  }

  const newVersion = `${major}.${minor}.${patch}`;
  pkg.version = newVersion;
  writeJson(PACKAGE_JSON_PATH, pkg);

  if (lock) {
    lock.version = newVersion;
    if (lock.packages?.['']) {
      lock.packages[''].version = newVersion;
      if (lock.packages[''].devDependencies?.electron) {
        lock.packages[''].devDependencies.electron = pkg.devDependencies.electron;
      }
    }
    writeJson(PACKAGE_LOCK_PATH, lock);
  }

  return { oldVersion, newVersion };
};

const createSha256 = (filePath) => {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return hash.digest('hex');
};

const buildReleaseNotes = (version, logs, checksum) => {
  const today = new Date().toISOString().split('T')[0];
  return [
    `# v${version} (${today})`,
    '',
    '## Changes',
    logs || '* No changes recorded.',
    '',
    '## Installation',
    `Download \`Prism-${version}-arm64.dmg\` and drag to Applications.`,
    '',
    '## Checksum (SHA-256)',
    `\`${checksum}\``,
  ].join('\n');
};

const ensureGhInstalled = () => {
  try {
    execFileSync('gh', ['--version'], { stdio: 'ignore' });
    return true;
  } catch (_error) {
    return false;
  }
};

const main = async () => {
  console.log('Starting Release Process...');

  const { lastTag, logs } = getGitLogs();
  console.log(`\nLast Tag: ${lastTag}`);
  console.log('Recent Commits:');
  console.log(logs);

  const args = process.argv.slice(2);
  const typeArg = args.find((arg) => arg.startsWith('--type='));

  let type = 'patch';
  if (typeArg) {
    type = typeArg.split('=')[1];
  } else {
    type = (await askQuestion('\nSelect release type (major/minor/patch) [patch]: ')) || 'patch';
  }

  if (!['major', 'minor', 'patch'].includes(type)) {
    console.error('Invalid type. Aborting.');
    process.exit(1);
  }

  const { newVersion } = updateVersion(type);
  console.log(`\nBumping version to v${newVersion}...`);

  console.log('\nBuilding and Packaging...');
  run('npm', ['run', 'dist']);

  const dmgName = `Prism-${newVersion}-arm64.dmg`;
  const dmgPath = path.join(ROOT_DIR, 'release', dmgName);
  const checksum = createSha256(dmgPath);
  const notesContent = buildReleaseNotes(newVersion, logs, checksum);

  fs.writeFileSync(RELEASE_NOTES_PATH, notesContent);
  console.log(`Release notes generated at ${RELEASE_NOTES_PATH}`);

  const latestReleaseData = {
    version: `v${newVersion}`,
    notes: notesContent,
    pub_date: new Date().toISOString(),
    url: `https://github.com/Halewwang/Prism-Browser-switching/releases/download/v${newVersion}/${dmgName}`,
    sha256: checksum,
    fileName: dmgName,
  };
  writeJson(LATEST_RELEASE_PATH, latestReleaseData);
  console.log('latest-release.json generated');

  console.log('\nCommitting version bump...');
  run('git', ['add', 'package.json', 'package-lock.json', 'RELEASE_NOTES.md', 'latest-release.json']);
  run('git', ['commit', '-m', `chore(release): v${newVersion}`]);
  run('git', ['tag', `v${newVersion}`]);

  console.log('\nPushing to GitHub...');
  run('git', ['push']);
  run('git', ['push', '--tags']);

  if (ensureGhInstalled()) {
    console.log('\nCreating GitHub Release...');
    run('gh', [
      'release',
      'create',
      `v${newVersion}`,
      dmgPath,
      '--title',
      `v${newVersion}`,
      '--notes-file',
      RELEASE_NOTES_PATH,
    ]);
    console.log('GitHub Release created successfully');
  } else {
    console.log('\nRelease Process Complete (Local Only)');
    console.log(`1. Go to: https://github.com/Halewwang/Prism-Browser-switching/releases/new`);
    console.log(`2. Select tag: v${newVersion}`);
    console.log(`3. Copy content from RELEASE_NOTES.md`);
    console.log(`4. Upload: ${dmgPath}`);
  }

  rl.close();
};

main();
