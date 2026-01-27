import sharp from 'sharp';
import fs from 'fs';

const svg = `
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <mask id="round-mask">
      <rect x="0" y="0" width="1024" height="1024" rx="220" ry="220" fill="white" />
    </mask>
  </defs>
  
  <!-- Background with rounded corners mask for macOS squircles (optional, but black square is usually fine if builder handles masking) -->
  <!-- Actually macOS Big Sur+ icons are rounded squares. If we provide a full square, macOS masks it. 
       But Figure 1 showed a small square inside white. This implies the previous PNG might have had transparency or wrong size.
       We will provide a FULL BLEED black square 1024x1024. macOS will crop it to squircle. -->
  <rect x="0" y="0" width="1024" height="1024" fill="black" />
  
  <g transform="translate(512, 512)">
    <!-- Common Attributes -->
    <!-- Vertical (0 deg) - Grey -->
    <rect x="-60" y="-380" width="120" height="760" rx="4" ry="4" fill="#B0B0B0" />
    
    <!-- Horizontal (90 deg) - Grey -->
    <rect x="-60" y="-380" width="120" height="760" rx="4" ry="4" fill="#B0B0B0" transform="rotate(90)" />
    
    <!-- Diagonal TL-BR (-45 deg) - Grey -->
    <rect x="-60" y="-380" width="120" height="760" rx="4" ry="4" fill="#B0B0B0" transform="rotate(-45)" />
    
    <!-- Diagonal BL-TR (45 deg) - Green -->
    <!-- Bright Neon Lime Green -->
    <rect x="-60" y="-380" width="120" height="760" rx="4" ry="4" fill="#76FF03" transform="rotate(45)" />
  </g>
</svg>
`;

sharp(Buffer.from(svg))
  .resize(1024, 1024)
  .png()
  .toFile('build/icon.png')
  .then(info => {
    console.log('✅ Icon generated successfully:', info);
  })
  .catch(err => {
    console.error('❌ Error generating icon:', err);
    process.exit(1);
  });
