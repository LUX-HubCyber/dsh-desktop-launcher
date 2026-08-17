<p align="center">
  <img src="assets/icon.png" alt="DeepSeek Harness Desktop" width="120"/>
</p>

<h1 align="center">🐋 DeepSeek Harness Desktop</h1>

<p align="center">
  A Windows desktop app that launches the <a href="https://github.com/deepseek-ai/deepseek-harness">DeepSeek Harness</a> Web UI with one click — double-click and go, no CLI required.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License: MIT"/></a>
  <img src="https://img.shields.io/badge/platform-Windows-0078D6.svg" alt="Platform: Windows"/>
  <img src="https://img.shields.io/badge/Electron-33.4.11-47848F.svg" alt="Electron 33.4.11"/>
  <img src="https://img.shields.io/badge/version-1.0.0-blue.svg" alt="Version 1.0.0"/>
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs welcome"/>
</p>

<p align="center">
  English | <a href="README.md"><b>简体中文</b></a>
</p>

> Double-click the `.exe` and it just works: it starts the Harness web service automatically, shows a splash screen
> with the DeepSeek whale logo and a 4-step progress indicator, then opens the UI in its **own desktop window** —
> no need to run `pnpm dsh web` or type a URL into a browser.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start (dev mode)](#quick-start-dev-mode)
- [Building the Windows Installer](#building-the-windows-installer)
- [Usage](#usage)
- [Configuration (optional)](#configuration-optional)
- [Icon & Logo](#icon--logo)
- [Troubleshooting](#troubleshooting)
- [How It Works](#how-it-works)
- [Directory Structure](#directory-structure)
- [Related Projects](#related-projects)
- [License](#license)

<!--
Screenshots (optional): drop images into docs/screenshots/ and uncomment the block below:

## Screenshots

![Splash screen](docs/screenshots/splash.png)
![Main window](docs/screenshots/main.png)
-->

## Features

- **Zero CLI**: double-click to run; the harness directory is auto-located and the service is started (equivalent to `pnpm dsh web`).
- **Splash screen**: shows the DeepSeek whale logo and a 4-step progress indicator (Init / Locate / Start service / Open UI), displayed for at least 0.9 s.
- **Service reuse**: if a healthy service is already running on `127.0.0.1:3080`, it is reused — no duplicate process.
- **Single instance**: launching again just brings the existing window to the front.
- **Clean shutdown**: closing the window stops the service process started by this app.
- **Brand icon**: white rounded square + DeepSeek whale + slanted "DSH" badge in the bottom-right corner, used for the window, taskbar, portable and installer builds.

## Requirements

- Windows 10 / 11
- **Development / building**: Node.js 22+ (required by `build.bat`), pnpm 9+ (lockfile version 9.0)
- An installed `deepseek-harness` source directory (must contain `apps/cli/src/bin.ts` and `node_modules`; see [Configuration](#configuration-optional))

## Quick Start (dev mode)

```powershell
pnpm install
pnpm start        # run directly in dev mode
```

For normal use no command is needed: just double-click a built `.exe` (see below).

## Building the Windows Installer

### Option 1: Build script (recommended)

Double-click `build.bat` (or run `.\build.ps1` in PowerShell). The script installs dependencies, builds and embeds the icon automatically. Outputs are written to `release\`:

| File | Description |
| --- | --- |
| `DeepSeek-Harness-1.0.0-portable.exe` | Portable build, double-click to run, no installation needed |
| `DeepSeek-Harness-Setup-1.0.0.exe` | Installer build, creates desktop/Start Menu shortcuts; default install folder `DeepSeek Harness Desktop` |

> `build.bat` / `build.ps1` invoke `pnpm run build:win`, which **automatically runs**
> `scripts\post-build-icon.ps1` after packaging: it embeds the DeepSeek whale icon and version info into the main
> executable with rcedit, then repackages the portable/installer builds (rcedit retries automatically to
> avoid transient file locks from antivirus/Defender).

### Option 2: Manual commands

```powershell
pnpm install
pnpm run build:win        # portable + installer (includes post-build icon embedding)
pnpm run build:portable   # portable only (no post-build; main exe keeps the default Electron icon)
pnpm run build:nsis       # installer only (same)
pnpm start                # run in dev mode
```

> If your network is slow, set mirrors and retry:
> ```powershell
> $env:ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/"
> $env:ELECTRON_BUILDER_BINARIES_MIRROR="https://npmmirror.com/mirrors/electron-builder-binaries/"
> ```

### Regenerating the icons

After editing the logo design, regenerate all icon assets with one command (run from the repository root):

```bat
scripts\build-icons.bat
```

## Usage

- Double-click `DeepSeek-Harness-1.0.0-portable.exe`: a splash screen appears first, then the Harness UI opens (default `http://127.0.0.1:3080`).
- If a Harness service is already running on port `3080`, it is reused automatically.
- Closing the window stops the service process started by this app.
- Menu "File → Open in browser" opens the UI in the system browser; external links in the UI open in the default browser automatically.

## Configuration (optional)

On first launch a config file is created at `%APPDATA%\dsh-desktop\settings.json` (also reachable via menu "Help → Open config file"):

```json
{
  "harnessPath": "deepseek-harness",
  "nodePath": "",
  "host": "127.0.0.1",
  "port": 3080
}
```

| Field | Description |
| --- | --- |
| `harnessPath` | Directory of the deepseek-harness sources (must contain `apps/cli/src/bin.ts` and `node_modules`). Three forms are supported: an **absolute path** (e.g. `C:\Program Files\DeepSeek\deepseek-harness`), a **directory name** (e.g. `deepseek-harness`, default) or a **trailing path** (e.g. `DeepSeek\deepseek-harness`). The latter two are resolved by searching the ancestor directories of the exe/project, all drive roots, the user home directory and the current directory |
| `nodePath` | Path to node.exe; leave empty for auto-detection (`node` / common install locations) |
| `host` / `port` | Harness web service address (`--port 0` lets the system pick a free port, but a fixed port is recommended for the desktop app) |

Environment variables can override these: `DSH_HARNESS_PATH`, `DSH_DESKTOP_PORT`, `DSH_DESKTOP_HOST`.

## Icon & Logo

The app icon is a "white rounded square + DeepSeek whale + slanted DSH badge at the bottom-right", available in two variants — **blue whale** and **black whale**; the **black whale** is the default:

| File | Description |
| --- | --- |
| `build/whale.svg` | Vector source of the DeepSeek whale (taken from the deepseek-harness website favicon) |
| `build/whale-blue.png` / `whale-black.png` | 512×512 finished logos (white rounded square + DeepSeek whale + slanted DSH) |
| `build/whale-blue.ico` / `whale-black.ico` | Corresponding multi-size ICOs (16–256) |
| `build/icon.png` / `build/icon.ico` | Icon actually used for packaging/embedding (black whale) |
| `assets/icon.png` | Runtime icon (splash logo, window icon; bundled into the asar) |

- `scripts\make-logo.ps1`: parses the DeepSeek whale path from `whale.svg`, draws the white rounded square, the DeepSeek whale, the slanted bottom-right badge and the DSH text, and outputs blue/black PNG variants.
- `scripts\make-icon.ps1`: scales the 512×512 PNG into a multi-size ICO (16–256, BMP/DIB entries with alpha preserved).
- The default installer folder name `DeepSeek Harness Desktop` is controlled by `build\installer.nsh`.
- Note: `make-logo.ps1` and `post-build-icon.ps1` contain Chinese comments and must be saved as UTF-8 **with BOM** (PowerShell 5.1 compatibility); keep the BOM after editing.

## Troubleshooting

- **Taskbar/desktop still shows the old icon after a rebuild**: this is the Windows icon cache; restart Explorer (or sign out/in) to refresh it.
- **Build fails with "rcedit icon embedding failed"**: usually antivirus/Defender briefly locks the freshly built exe; the script retries up to 8 times automatically. If it still fails, make sure no DeepSeek Harness instance is running and retry.
- **The build log shows `⨯ cannot execute ... rcedit ... Unable to commit changes`**: this is the expected transient lock (antivirus/Defender) during electron-builder's first-pass icon embedding. The post-build step re-embeds the icon with up to 8 automatic retries and repackages, so the final artifacts are unaffected — this message can be ignored.
- **Build fails with "file in use"**: close any running DeepSeek Harness first (it locks files under `release\win-unpacked`).

## How It Works

The main process (`electron/main.js`):

1. Reads the configuration (`settings.json` / environment variables) and locates the harness directory and the node executable.
2. Shows a splash screen with a 4-step progress indicator.
3. Probes the target port; reuses the service if it is already healthy.
4. Otherwise spawns `node --import tsx/esm apps/cli/src/bin.ts web` (equivalent to `pnpm dsh web`), passing `--port` per the config.
5. Polls until the service is ready, then loads the UI in a built-in window (window title fixed to `DeepSeek Harness Desktop`).
6. Stops the service started by this app on exit; a single-instance lock brings the existing window to the front on relaunch.

## Directory Structure

```
dsh-desktop-launcher/
├── electron/main.js        # Electron main process (service startup + splash + window + menu)
├── assets/icon.png         # Runtime icon (splash logo / window icon)
├── package.json            # Dependencies, scripts and electron-builder config
├── pnpm-lock.yaml          # Lockfile (commit it for reproducible installs)
├── pnpm-workspace.yaml     # pnpm workspace config
├── .npmrc                  # pnpm config (store redirected into the workspace)
├── .gitattributes          # Line-ending policy (LF/CRLF normalization)
├── .gitignore
├── CHANGELOG.md            # Changelog
├── LICENSE                 # MIT license
├── README.md / README.en.md
├── build/                  # Build resources
│   ├── whale.svg           #   Vector source of the DeepSeek whale
│   ├── whale-blue/black.png/.ico   # Blue/black whale logos and ICOs
│   ├── icon.png / icon.ico #   Icon actually used (black whale)
│   └── installer.nsh       #   NSIS customization (install folder name, etc.)
├── scripts/
│   ├── make-logo.ps1       # Generates the DeepSeek whale logo PNGs (blue/black)
│   ├── make-icon.ps1       # PNG → multi-size ICO
│   ├── build-icons.bat     # One-click regeneration of all icons
│   └── post-build-icon.ps1 # Post-build icon embedding + version info + repackaging
├── build.bat / build.ps1   # One-click build scripts
└── release/                # Build outputs (.exe, ignored by .gitignore)
```

## Related Projects

- [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) — the Harness web service this app launches.

## License

[MIT](LICENSE) © 2026 LUX-HubCyber
