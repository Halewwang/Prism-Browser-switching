
const { exec } = require('child_process');
const fs = require('fs');

async function getSourceAppInfo() {
  return new Promise((resolve) => {
    exec('lsappinfo visibleProcessList', async (error, stdout) => {
      let sourceAppName = 'Unknown';
      let sourceAppPath = '';

      if (!error && stdout) {
        console.log('Raw output:', stdout);
        // Output format: ASN:0x...-"Name": ASN:0x...-"Name": ...
        const matches = stdout.match(/-"([^"]+)"/g);
        if (matches) {
          const appNames = matches.map(m => m.slice(2, -1)); // Remove -" and "
          console.log('Detected apps:', appNames);
          // Filter out Prism itself and system apps
          const ignoreList = ['Prism', 'Electron', 'Finder', '访达', 'Dock', 'SystemUIServer', 'TRAE', 'Terminal', 'iTerm2', 'Xcode'];
          
          for (const name of appNames) {
             if (!ignoreList.includes(name)) {
                sourceAppName = name;
                break;
             }
          }
        }
      }
      
      console.log('Selected Source App:', sourceAppName);

      if (sourceAppName !== 'Unknown') {
          try {
             const pathOutput = await new Promise((res) => {
                 exec(`lsappinfo info -only bundlepath "${sourceAppName}"`, (e, out) => res(out || ''));
             });
             console.log('Path output:', pathOutput);
             const pathMatch = pathOutput.match(/"LSBundlePath"="([^"]+)"/);
             if (pathMatch) {
                 sourceAppPath = pathMatch[1];
             }
          } catch (e) {
              console.error('Failed to get app path', e);
          }
      }
      
      console.log('Final Result:', { name: sourceAppName, path: sourceAppPath });
      resolve({ name: sourceAppName, path: sourceAppPath });
    });
  });
}

getSourceAppInfo();
