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

Direct version links:

- [v1.4.0 (current): GZWhisper-Installer-1.4.dmg](https://github.com/globa-me/GZWhisper/releases/download/v1.4.0/GZWhisper-Installer-1.4.dmg)
- [v1.4.0 (current): GZWhisper-macOS-1.4.zip](https://github.com/globa-me/GZWhisper/releases/download/v1.4.0/GZWhisper-macOS-1.4.zip)
- [v1.3.0 (legacy): GZWhisper-Installer-1.3.dmg](https://github.com/globa-me/GZWhisper/releases/download/v1.3.0/GZWhisper-Installer-1.3.dmg)
- [v1.3.0 (legacy): GZWhisper-macOS-1.3.zip](https://github.com/globa-me/GZWhisper/releases/download/v1.3.0/GZWhisper-macOS-1.3.zip)
- [v1.2.0 (legacy): GZWhisper-Installer.dmg](https://github.com/globa-me/GZWhisper/releases/download/v1.2.0/GZWhisper-Installer.dmg)
- [v1.1.0 (legacy, no recording): GZWhisper-Installer-1.1.dmg](https://github.com/globa-me/GZWhisper/releases/download/v1.1.0/GZWhisper-Installer-1.1.dmg)

Install:

1. Open `GZWhisper-Installer.dmg` (or versioned `GZWhisper-Installer-1.4.dmg`).
2. Drag `GZWhisper.app` to `Applications`.
3. Launch the app from `Applications`. If macOS blocks the app, open `Run_If_Blocked.txt` from the DMG.

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
- For video transcription, place `ffmpeg.exe` next to `GZWhisper.exe` or add it to `PATH`.
- See the full Windows user guide: [`docs/WINDOWS_PORTABLE.md`](docs/WINDOWS_PORTABLE.md)

### Build Windows portable package (on Windows host)

```powershell
.\scripts\package_windows_portable.ps1
```

Or:

```cmd
scripts\package_windows_portable.cmd
```

Output:
- `build/GZWhisper-windows-portable/`
- `build/GZWhisper-windows-portable.zip`

## Maintainer: Build Release DMG (macOS)

This section is for maintainers preparing release artifacts.

### Build DMG installer

```bash
./scripts/build_dmg.sh
```

Output: `build/GZWhisper-Installer-1.4.dmg`

Optional version/build override for release builds:

```bash
APP_VERSION=1.4 APP_BUILD=310326 ./scripts/build_app.sh
./scripts/build_dmg.sh
```

`APP_BUILD` now uses a date code in `DDMMYY` format.

The shipped app now uses the stable macOS app name and bundle id so it replaces the previous install cleanly:
- app bundle: `build/GZWhisper.app`
- bundle id: `com.gzakharov.gzwhisper`
- installer: `build/GZWhisper-Installer-1.4.dmg`

If you need a legacy non-versioned app name for a single-track install, override:

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

Output: `build/GZWhisper-macOS-1.4.zip`

### 4) Build DMG installer

```bash
./scripts/build_dmg.sh
```

Output: `build/GZWhisper-Installer-1.4.dmg`

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

### 2026-03-31 (v1.4, build 310326)

- Added history search for faster lookup of saved jobs and recordings.
- Added inline rename for history entries while preserving original files on disk.
- Updated the macOS app version to `1.4` and changed the build label to a `DDMMYY` date code.
- Returned the macOS app bundle name to `GZWhisper.app` so new installs replace the previous app in `Applications`.

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
