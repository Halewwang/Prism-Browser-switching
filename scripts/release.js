import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';
import readline from 'readline';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.join(__dirname, '..');
const PACKAGE_JSON_PATH = path.join(ROOT_DIR, 'package.json');
const RELEASE_NOTES_PATH = path.join(ROOT_DIR, 'RELEASE_NOTES.md');

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

const askQuestion = (query) => new Promise((resolve) => rl.question(query, resolve));

const run = (command) => {
    try {
        console.log(`running: ${command}`);
        execSync(command, { stdio: 'inherit', cwd: ROOT_DIR });
    } catch (e) {
        console.error(`❌ Command failed: ${command}`);
        process.exit(1);
    }
};

const getGitLogs = () => {
    try {
        // Get commits since last tag
        const lastTag = execSync('git describe --tags --abbrev=0', { cwd: ROOT_DIR, encoding: 'utf8' }).trim();
        const logs = execSync(`git log ${lastTag}..HEAD --pretty=format:"* %s (%h)"`, { cwd: ROOT_DIR, encoding: 'utf8' });
        return { lastTag, logs };
    } catch (e) {
        // Fallback if no tags exist
        const logs = execSync('git log --pretty=format:"* %s (%h)" -n 10', { cwd: ROOT_DIR, encoding: 'utf8' });
        return { lastTag: 'v0.0.0', logs };
    }
};

const updateVersion = (type) => {
    const pkg = JSON.parse(fs.readFileSync(PACKAGE_JSON_PATH, 'utf8'));
    const oldVersion = pkg.version;
    let [major, minor, patch] = oldVersion.split('.').map(Number);

    if (type === 'major') major++;
    else if (type === 'minor') minor++;
    else patch++; // default to patch

    // Reset lower versions
    if (type === 'major') { minor = 0; patch = 0; }
    if (type === 'minor') { patch = 0; }

    const newVersion = `${major}.${minor}.${patch}`;
    pkg.version = newVersion;
    fs.writeFileSync(PACKAGE_JSON_PATH, JSON.stringify(pkg, null, 2) + '\n');
    return { oldVersion, newVersion };
};

const main = async () => {
    console.log('🚀 Starting Release Process...');
    
    // 1. Determine Version Bump
    const { lastTag, logs } = getGitLogs();
    console.log(`\nLast Tag: ${lastTag}`);
    console.log('Recent Commits:');
    console.log(logs);
    
    const type = await askQuestion('\nSelect release type (major/minor/patch) [patch]: ') || 'patch';
    if (!['major', 'minor', 'patch'].includes(type)) {
        console.error('Invalid type. Aborting.');
        process.exit(1);
    }

    // 2. Bump Version
    const { newVersion } = updateVersion(type);
    console.log(`\n📦 Bumping version to v${newVersion}...`);

    // 3. Generate Release Notes
    const today = new Date().toISOString().split('T')[0];
    const notesContent = `# v${newVersion} (${today})\n\n## Changes\n${logs}\n\n## Installation\nDownload \`Prism-${newVersion}-arm64.dmg\` and drag to Applications.`;
    
    fs.writeFileSync(RELEASE_NOTES_PATH, notesContent);
    console.log(`✅ Release notes generated at ${RELEASE_NOTES_PATH}`);

    // 4. Build and Package
    console.log('\n🏗️  Building and Packaging...');
    run('npm run dist');

    // 5. Commit and Tag
    console.log('\n💾 Committing version bump...');
    run('git add package.json RELEASE_NOTES.md');
    run(`git commit -m "chore(release): v${newVersion}"`);
    run(`git tag v${newVersion}`);

    // 6. Push
    console.log('\n🚀 Pushing to GitHub...');
    run('git push && git push --tags');

    console.log('\n✨ Release Process Complete!');
    console.log(`1. Go to: https://github.com/Halewwang/Prism-Browser-switching/releases/new`);
    console.log(`2. Select tag: v${newVersion}`);
    console.log(`3. Copy content from RELEASE_NOTES.md`);
    console.log(`4. Upload: release/Prism-${newVersion}-arm64.dmg`);
    
    rl.close();
};

main();
