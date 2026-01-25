import { execSync } from 'child_process';

const run = (command) => {
    try {
        execSync(command, { stdio: 'inherit' });
    } catch (e) {
        // If git commit fails (empty), we don't want to exit
        if (command.startsWith('git commit')) {
            return false;
        }
        console.error(`❌ Command failed: ${command}`);
        process.exit(1);
    }
    return true;
};

// Get commit message from args or generate default
const args = process.argv.slice(2);
const message = args.join(' ') || `Auto update: ${new Date().toLocaleString()}`;

console.log('🔄 [Sync] Starting GitHub sync...');

// 1. Add all changes
console.log('📦 Adding files...');
run('git add .');

// 2. Commit
console.log(`💾 Committing with message: "${message}"`);
const committed = run(`git commit -m "${message}"`);

// 3. Push
if (committed) {
    console.log('🚀 Pushing to remote...');
    run('git push origin main');
    console.log('✅ Sync complete!');
} else {
    console.log('⚠️ Nothing to commit. Checking for unpushed commits...');
    // Try push anyway in case there are unpushed commits
    run('git push origin main');
    console.log('✅ Sync complete!');
}
