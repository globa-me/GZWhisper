# GZWhisper

GZWhisper is a local-first speech app for transcription of audio/video files.

This repository includes desktop apps for three platforms:
- `macOS` app (SwiftUI): `Sources/`
- `Linux` app (Python + Tkinter): `linux/gzwhisper_linux.py`
- `Windows` app (portable `.exe`, built from Python + Tkinter): `linux/gzwhisper_linux.py`

After the model is downloaded, transcription runs on the user's machine.

## What it does
### (macOS version is a priority)

- Download a Whisper model from Hugging Face, or connect an existing local model.
- Accept audio and video files.
- Extract audio from video automatically.
- Record audio directly in the macOS app:
  - `System + microphone`
  - `System only`
  - `Microphone only`
- Pause and resume recording, then save recorded audio next to transcripts.
- Transcribe locally and save output as `TXT` or `JSON`.
- Keep a history of jobs and recordings with type badges (`t`, `a`, `t+a`) and quick actions.
- Auto-switch app language based on system locale:
  - Russian (`ru`)
  - English (`en`)
  - Chinese (`zh`)

## Download (macOS)

Current macOS package target is `arm64` only (Apple Silicon).

Download the latest release files:

- [Latest DMG: GZWhisper-Installer.dmg](https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-Installer.dmg)
- [Latest ZIP: GZWhisper-macOS.zip](https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-macOS.zip)

Published release links:

- [v1.4.1 (current): GZWhisper-Installer-1.4.1.dmg](https://github.com/globa-me/GZWhisper/releases/download/v1.4.1/GZWhisper-Installer-1.4.1.dmg)
- [v1.4.1 (current): GZWhisper-macOS-1.4.1.zip](https://github.com/globa-me/GZWhisper/releases/download/v1.4.1/GZWhisper-macOS-1.4.1.zip)
- [v1.4.0: GZWhisper-Installer-1.4.dmg](https://github.com/globa-me/GZWhisper/releases/download/v1.4.0/GZWhisper-Installer-1.4.dmg)
- [v1.4.0: GZWhisper-macOS-1.4.zip](https://github.com/globa-me/GZWhisper/releases/download/v1.4.0/GZWhisper-macOS-1.4.zip)
- [v1.2.0 (legacy): GZWhisper-Installer.dmg](https://github.com/globa-me/GZWhisper/releases/download/v1.2.0/GZWhisper-Installer.dmg)
- [v1.1.0 (legacy, no recording): GZWhisper-Installer-1.1.dmg](https://github.com/globa-me/GZWhisper/releases/download/v1.1.0/GZWhisper-Installer-1.1.dmg)

Current source tree version in this repository: `v1.4.2` (`build 150426`).

Install:

1. Open `GZWhisper-Installer.dmg` (or versioned `GZWhisper-Installer-1.4.1.dmg`).
2. Drag `GZWhisper.app` to `Applications`.
3. Eject the installer image.
4. Launch the app from `Applications`.

If macOS blocks the app:

1. In `Applications`, right-click `GZWhisper.app` and choose `Open`.
2. If needed, go to `System Settings -> Privacy & Security` and click `Open Anyway`.
3. Use `Enable_GZWhisper.command` only as a local cleanup helper for the copied app in `Applications`.

For unsigned or non-notarized builds distributed to other Macs, prefer the ZIP archive over the DMG. The hidden Gatekeeper `Anywhere` flow is not a stable install path on current macOS versions.

## Quick Start (Linux)

### 1) Install system dependencies

Fedora:

```bash
sudo dnf install -y python3 python3-pip python3-tkinter ffmpeg
```

Ubuntu / Debian:

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-tk ffmpeg
```

### 2) Install the app

```bash
./scripts/install_linux.sh
```

This creates:
- launcher: `~/.local/bin/gzwhisper-linux`
- desktop entry: `~/.local/share/applications/gzwhisper-linux.desktop`

### 3) Run

```bash
gzwhisper-linux
```

If the command is not in `PATH`, run:

```bash
~/.local/bin/gzwhisper-linux
```

### 4) Uninstall

```bash
./scripts/uninstall_linux.sh
```

### Optional: build a distributable archive

```bash
./scripts/package_linux.sh
```

Output: `build/GZWhisper-linux.tar.gz`

## Quick Start (Windows Portable version, still in development)

Run the portable executable:

```powershell
GZWhisper.exe
```

Notes:
- No installer is required.
- Current portable builds bundle `ffmpeg.exe` by default for video transcription.
- If you build with `-SkipBundledFfmpeg`, place `ffmpeg.exe` next to `GZWhisper.exe` or add it to `PATH`.
- See the full Windows user guide: [`docs/WINDOWS_PORTABLE.md`](docs/WINDOWS_PORTABLE.md)

### Build Windows portable package (on Windows host)

```powershell
.\scripts\package_windows_portable.ps1
```

The script now auto-detects a working local Python, bundles `ffmpeg.exe` into the portable folder by default, and copies the ffmpeg license file alongside it.

Or:

```cmd
scripts\package_windows_portable.cmd
```

Output:
- `build/GZWhisper-windows-portable/`
- `build/GZWhisper-windows-portable.zip`

Optional:

```powershell
.\scripts\package_windows_portable.ps1 -FfmpegExe "C:\tools\ffmpeg\bin\ffmpeg.exe"
.\scripts\package_windows_portable.ps1 -SkipBundledFfmpeg
```

## Maintainer: Build Release DMG (macOS)

This section is for maintainers preparing release artifacts.

### Build DMG installer

```bash
./scripts/build_dmg.sh
```

Output: `build/GZWhisper-Installer-1.4.2.dmg`

Optional version/build override for release builds:

```bash
APP_VERSION=1.4.2 APP_BUILD=150426 ./scripts/build_app.sh
./scripts/build_dmg.sh
```

Signing behavior:

- `./scripts/build_app.sh` now tries to auto-detect a signing identity.
- Preferred: `Developer ID Application` for public builds and permission persistence across updates.
- By default, if no `Developer ID Application` is available, the script falls back to ad-hoc signing.
- `Apple Development` is only for local developer installs on your own Mac and is opt-in via `ALLOW_APPLE_DEVELOPMENT_FALLBACK=1`.
- Explicit ad-hoc signing is still available with `SIGNING_IDENTITY=-`, but macOS may treat privacy permissions like Screen Recording and System Audio as new on every update.

Optional notarization for public DMG builds:

```bash
APP_VERSION=1.4.2 APP_BUILD=150426 ./scripts/build_app.sh
NOTARYTOOL_PROFILE=my-notary-profile ./scripts/build_dmg.sh
```

`NOTARYTOOL_PROFILE` must point to credentials previously stored with `xcrun notarytool store-credentials`, and notarization should only be used together with a `Developer ID Application` signed app.

`APP_BUILD` uses a date code in `DDMMYY` format.

The shipped macOS app now keeps the stable install name and bundle id so dragging a new release into `Applications` updates the previous app in place:
- app bundle: `build/GZWhisper.app`
- bundle id: `com.gzakharov.gzwhisper`
- installer: `build/GZWhisper-Installer-1.4.2.dmg`

If you need a non-versioned installer filename and volume title for release publishing, override:

```bash
APP_BUNDLE_NAME=GZWhisper APP_DISPLAY_NAME=GZWhisper APP_BUNDLE_ID=com.gzakharov.gzwhisper ./scripts/build_app.sh
DMG_NAME=GZWhisper-Installer APP_BUNDLE_NAME=GZWhisper APP_TITLE=GZWhisper ./scripts/build_dmg.sh
```

## Build from Source (macOS, developers)

Current macOS packaging target is `arm64` only (Apple Silicon).

### 1) Prepare embedded Python runtime

```bash
./scripts/prepare_embedded_python.sh
```

This script copies `Python.framework` into `Resources/` and optionally downloads a local wheelhouse for offline dependency install.
Use Apple Silicon Python (`arm64`). Example:

```bash
PYTHON_BIN=/opt/homebrew/bin/python3 ./scripts/prepare_embedded_python.sh
```

### 2) Build app bundle

```bash
./scripts/make_icon.sh
./scripts/build_app.sh
```

Output: `build/GZWhisper.app`

### 3) Build ZIP for distribution

```bash
./scripts/package_zip.sh
```

Output: `build/GZWhisper-macOS-1.4.2.zip`

The ZIP now includes:
- `GZWhisper.app`
- `Install_Instructions.txt`
- `Run_If_Blocked.txt`
- `Enable_GZWhisper.command`

### 4) Build DMG installer

```bash
./scripts/build_dmg.sh
```

Output: `build/GZWhisper-Installer-1.4.2.dmg`

# First run (all platforms)

1. Open the app.
2. Click **Download model** (or connect an existing local model folder).
3. Wait for one-time environment setup and dependency install.
4. Pick an audio/video file and run transcription.

## Notes

- For macOS builds with embedded wheelhouse, Python dependencies install without extra system prompts.
- Internet is needed for first-time model download (and for dependency install only if no wheelhouse is bundled).
- Once the model is local, transcription can run offline.
- Linux video transcription requires `ffmpeg`.
- Windows video transcription requires `ffmpeg.exe` (next to app or in `PATH`).

## Project layout

- `Sources/` — macOS app source code.
- `linux/` — Linux app source code.
- `Resources/transcription_worker.py` — shared worker for model download/validation/transcription.
- `scripts/` — build, package, install, uninstall scripts.

## Changelog

### 2026-04-15 (v1.4.2, build 150426)

- Added queue cancellation for macOS transcription runs.
- Warns when newly added media files are especially large or long-running.
- Updated macOS packaging defaults and output names to `v1.4.2`.
- Improved signing, ZIP/DMG packaging, and notarization guidance for public macOS builds.
- Simplified `Enable_GZWhisper.command` so it cleans the copied app locally instead of changing Gatekeeper policy.

### 2026-04-01 (v1.4.1, build 310401)

- Fixed macOS transcription after app updates by recreating stale or broken local Python virtual environments automatically.
- Added a debug menu in the footer to copy diagnostics and open the app data folder.
- Kept the shipped macOS bundle name as `GZWhisper.app` so updates replace the installed app without regranting permissions.

### 2026-03-31 (v1.4.0, build 310326)

- Added history search for faster lookup of saved jobs and recordings.
- Added inline rename for history entries while preserving original files on disk.
- Updated the macOS app version to `1.4` and changed the build label to a `DDMMYY` date code.

### 2026-02-27 (v1.3, build 1)

- Updated macOS packaging defaults so `v1.3` can be installed alongside `v1.2` (`GZWhisper-1.3.app`, `com.gzakharov.gzwhisper.v13`).
- Updated app version to `1.3`.

### 2026-02-26 (v1.2, build 4)

- Added macOS audio recording modes: `System + microphone`, `System only`, `Microphone only`.
- Added recording controls (`Start`, `Pause`, `Resume`, `Stop`) and saving recorded audio into transcripts folder.
- Added history type badges (`t`, `a`, `t+a`) with tooltips and quick actions for audio/transcript files.
- Added queue-from-history action for recorded audio files.
- Added footer links on macOS: `GitHub | Built by Gennadiy Zakharov`.
- Fixed crash when starting `System + microphone` recording after permissions were granted.
- Simplified transcription loading UI to a single active spinner in history.

### 2026-02-16 (v1.1, build 2)

- Added macOS transcription queue and history with persisted items, status states, and quick file actions from the app.
- Added streaming transcription progress events (`processed_seconds` / `total_seconds`) and ETA display in the UI.
- Improved runtime bootstrap: app now searches bundled Python first, falls back to known system locations, and reports runtime issues.
- Added optional offline dependency install from bundled `Resources/wheelhouse`.
- Added `scripts/prepare_embedded_python.sh` and updated `scripts/build_app.sh` for Apple Silicon (`arm64`) packaging with embedded Python assets.
- Expanded localized strings (EN/RU/ZH) for history, queue, progress, and runtime diagnostics.
- Updated Linux subtitle text to match desktop positioning and refreshed `.gitignore` for embedded runtime artifacts.
- Synced Linux app to queue/history workflow with persisted transcript history and streaming progress/ETA.
- Added Windows portable build scripts: `scripts/package_windows_portable.ps1` and `scripts/package_windows_portable.cmd`.
- Added frozen worker relay mode (`--worker-relay`) to support single portable executable runtime without system Python.

## License

MIT
