# GZWhisper

GZWhisper is a local-first speech-to-text app for audio and video files.

This repository includes desktop apps for three platforms:
- `macOS` app (SwiftUI): `Sources/`
- `Linux` app (Python + Tkinter): `linux/gzwhisper_linux.py`
- `Windows` app (portable `.exe`, built from Python + Tkinter): `linux/gzwhisper_linux.py`

After the model is downloaded, transcription runs on the user's machine.

## What it does

- Download a Whisper model from Hugging Face, or connect an existing local model.
- Show download progress while the model is being fetched.
- Accept audio and video files.
- Extract audio from video automatically.
- Transcribe locally and save output as `TXT` or `JSON`.
- Auto-switch app language based on system locale:
  - Russian (`ru`)
  - English (`en`)
  - Chinese (`zh`)

## Download (macOS)

Current macOS package target is `arm64` only (Apple Silicon).

Download the latest installer DMG:

- [GZWhisper-Installer.dmg](https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-Installer.dmg)

Install:

1. Open `GZWhisper-Installer.dmg`.
2. Drag `GZWhisper.app` to `Applications`.
3. Launch the app from `Applications`.

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

## Quick Start (Windows Portable)

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

Output: `build/GZWhisper-Installer.dmg`

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

Output: `build/GZWhisper-macOS.zip`

### 4) Build DMG installer

```bash
./scripts/build_dmg.sh
```

Output: `build/GZWhisper-Installer.dmg`

## First run (all platforms)

1. Open the app.
2. Click **Download model** (or connect an existing local model folder).
3. Wait for one-time environment setup and dependency install.
4. Pick an audio/video file and run transcription.

## Notes for non-technical users

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

### 2026-02-26

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

No license file yet. If you want, add `MIT` as a quick default.
