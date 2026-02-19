# GZWhisper

GZWhisper is a local-first speech-to-text app for audio and video files.

This repository includes two desktop apps:
- `macOS` app (SwiftUI): `Sources/`
- `Linux` app (Python + Tkinter): `linux/gzwhisper_linux.py`

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

## Quick Start (macOS)

### Build app bundle

```bash
./scripts/make_icon.sh
./scripts/build_app.sh
```

Output: `build/GZWhisper.app`

### Build ZIP for distribution

```bash
./scripts/package_zip.sh
```

Output: `build/GZWhisper-macOS.zip`

### Build DMG installer

```bash
./scripts/build_dmg.sh
```

Output: `build/GZWhisper-Installer.dmg`

## First run (both platforms)

1. Open the app.
2. Click **Download model** (or connect an existing local model folder).
3. Wait for one-time environment setup and dependency install.
4. Pick an audio/video file and run transcription.

## Notes for non-technical users

- Internet is needed only for first-time setup (model + Python dependencies).
- Once the model is local, transcription can run offline.
- Linux video transcription requires `ffmpeg`.

## Project layout

- `Sources/` — macOS app source code.
- `linux/` — Linux app source code.
- `Resources/transcription_worker.py` — shared worker for model download/validation/transcription.
- `scripts/` — build, package, install, uninstall scripts.

## License

No license file yet. If you want, add `MIT` as a quick default.
