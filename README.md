
# LinkMaster Pro - macOS Browser Router

A native macOS utility to intercept links and route them to specific browsers based on source applications or URL patterns.

## ⚡️ One-Click Installation

To set up the development environment and launch the app immediately, run:

```bash
git clone <this-repo> && cd linkmaster && npm install && npm start
```

## 🛠 Features
- **Smart Popups**: Instant browser selector with keyboard shortcut support.
- **App Detection**: Automatically identifies if the link came from Slack, Discord, WeChat, etc.
- **Rule Engine**: Create permanent routing rules for repetitive tasks.
- **Performance**: Zero-latency native Electron implementation (AI removed for speed).

## 📦 Distribute
To build a production-ready `.dmg` installer:
```bash
npm run dist
```
The installer will be available in the `/release` directory.
