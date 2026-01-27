import sharp from 'sharp';
import fs from 'fs';
import path from 'path';

// 输入文件
const inputFile = path.join(process.cwd(), 'build', 'logo.svg');
// 输出文件
const outputFile = path.join(process.cwd(), 'build', 'icon.png');

console.log('🖼️  Processing icon...');
console.log(`📥 Input: ${inputFile}`);
console.log(`📤 Output: ${outputFile}`);

if (!fs.existsSync(inputFile)) {
    console.error('❌ Error: build/logo.svg not found!');
    process.exit(1);
}

// Convert SVG to 1024x1024 PNG
sharp(inputFile)
  .resize(1024, 1024)
  .png()
  .toFile(outputFile)
  .then(info => {
    console.log('✅ Icon generated successfully:', info);
  })
  .catch(err => {
    console.error('❌ Error generating icon:', err);
    process.exit(1);
  });
