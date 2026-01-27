import sharp from 'sharp';
import path from 'path';
import fs from 'fs';

const inputFile = path.join(process.cwd(), 'public/tray_icon.png');
const outputBase = path.join(process.cwd(), 'public/trayTemplate.png');
const output2x = path.join(process.cwd(), 'public/trayTemplate@2x.png');

if (!fs.existsSync(inputFile)) {
    console.error('❌ public/tray_icon.png not found. Please provide the source file.');
    process.exit(1);
}

// Generate 1x (22x22)
sharp(inputFile)
    .resize(22, 22)
    .toFile(outputBase)
    .then(() => console.log('✅ Generated trayTemplate.png (22x22)'))
    .catch(err => console.error(err));

// Generate 2x (44x44)
sharp(inputFile)
    .resize(44, 44)
    .toFile(output2x)
    .then(() => console.log('✅ Generated trayTemplate@2x.png (44x44)'))
    .catch(err => console.error(err));
