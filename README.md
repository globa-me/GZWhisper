# GZWhisper

GZWhisper is a local-first speech app for transcription of audio/video files. The stable app is **tested ONLY on macOS**. The Windows version is partially working, but still needs fixes and proper testing.

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

## macOS: download and run

**Current release: `v1.5.0` (build `250826`).** It supports Apple Silicon Macs (`arm64`) running macOS 12 or later. Recording system audio requires macOS 13 or later.

Choose one of the files below. The contents are identical; DMG is the most familiar installation format, while ZIP is often more convenient when macOS has to approve an unsigned or non-notarized app.

- [Latest DMG: GZWhisper-Installer-1.5.0.dmg](https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-Installer-1.5.0.dmg)
- [Latest ZIP: GZWhisper-macOS-1.5.0.zip](https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-macOS-1.5.0.zip)
- [v1.5.0 DMG](https://github.com/globa-me/GZWhisper/releases/download/v1.5.0/GZWhisper-Installer-1.5.0.dmg)
- [v1.5.0 ZIP](https://github.com/globa-me/GZWhisper/releases/download/v1.5.0/GZWhisper-macOS-1.5.0.zip)

Older releases are available on the [Releases page](https://github.com/globa-me/GZWhisper/releases).

### Install a ready-made app (no coding required)

1. Download the DMG or ZIP above from this repository's Releases page.
2. For a DMG, open it and drag `GZWhisper.app` to the `Applications` shortcut. For a ZIP, double-click it in Finder, then move `GZWhisper.app` to `Applications`.
3. Eject the DMG if you used one, then open GZWhisper from `Applications`.

### If macOS says the app cannot be opened

This is expected for an app that macOS cannot verify with Apple notarization. It does not mean the app is damaged. Only use the following steps for a file downloaded from this official GitHub repository.

1. In `Applications`, Control-click (or right-click) `GZWhisper.app` and choose **Open**.
2. Click **Open** in the confirmation dialog. This normally saves an exception for this app.
3. If the button is not offered, try opening the app once and dismiss the warning. Open **System Settings → Privacy & Security**, scroll to the **Security** section, then click **Open Anyway** next to GZWhisper. Confirm with Touch ID or your Mac password.

Do not disable Gatekeeper globally. The ZIP/DMG also includes `Enable_GZWhisper.command` and `Run_If_Blocked.txt` as a last-resort local helper; the System Settings method above is preferred.

When GZWhisper asks for recording access, allow the relevant permissions in **System Settings → Privacy & Security → Microphone** and, for system audio, **Screen & System Audio Recording**. Restart the app after changing a permission.

### Build the current version yourself (Apple Silicon)

Building from source is the best option if you want the exact current code, or prefer to run an app compiled on your own Mac. The build script uses your local Apple Development signing certificate when available and otherwise applies an ad-hoc signature. A self-built app is usually not quarantined; if macOS still blocks it, use the same **Privacy & Security → Open Anyway** steps above.

1. Install Apple's Command Line Tools in Terminal:

   ```bash
   xcode-select --install
   ```

2. Install Apple Silicon Python 3.12. With [Homebrew](https://brew.sh/):

   ```bash
   brew install python@3.12
   ```

3. Clone the project and prepare its local Python runtime. This one-time step also downloads the wheels used by the app:

   ```bash
   git clone https://github.com/globa-me/GZWhisper.git
   cd GZWhisper
   PYTHON_BIN="$(brew --prefix python@3.12)/bin/python3.12" ./scripts/prepare_embedded_python.sh
   ```

4. Build and open the app:

   ```bash
   ./scripts/make_icon.sh
   ./scripts/build_app.sh
   open build/GZWhisper.app
   ```

The result is `build/GZWhisper.app`. To make a ZIP or DMG from your build, run `./scripts/package_zip.sh` or `./scripts/build_dmg.sh`.

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

### Maintainer: repository safety check

Run this before merging release or packaging changes:

```bash
./scripts/check_repo_security.sh
```

It checks that generated `build/` artifacts are not tracked, scans tracked source files for obvious secrets, blocks Gatekeeper allow-list mutations, and validates shell script syntax.

## Maintainer: Build Release DMG (macOS)

This section is for maintainers preparing release artifacts.

### Build DMG installer

```bash
./scripts/build_dmg.sh
```

Output: `build/GZWhisper-Installer-1.5.0.dmg`

Optional version/build override for release builds:

```bash
APP_VERSION=1.5.0 APP_BUILD=250826 ./scripts/build_app.sh
./scripts/build_dmg.sh
```

Signing behavior:

- `./scripts/build_app.sh` now tries to auto-detect a signing identity.
- Preferred: `Developer ID Application` for public builds and permission persistence across updates.
- By default, if no `Developer ID Application` is available, the script uses `Apple Development` when present.
- `Apple Development` is used automatically for local developer installs when `Developer ID Application` is unavailable; set `ALLOW_APPLE_DEVELOPMENT_FALLBACK=0` to force ad-hoc fallback.
- Explicit ad-hoc signing is still available with `SIGNING_IDENTITY=-`, but macOS may treat privacy permissions like Screen Recording and System Audio as new on every update.

Optional notarization for public DMG builds:

```bash
APP_VERSION=1.5.0 APP_BUILD=250826 ./scripts/build_app.sh
NOTARYTOOL_PROFILE=my-notary-profile ./scripts/build_dmg.sh
```

`NOTARYTOOL_PROFILE` must point to credentials previously stored with `xcrun notarytool store-credentials`, and notarization should only be used together with a `Developer ID Application` signed app.

`APP_BUILD` uses a date code in `DDMMYY` format.

The shipped macOS app now keeps the stable install name and bundle id so dragging a new release into `Applications` updates the previous app in place:
- app bundle: `build/GZWhisper.app`
- bundle id: `com.gzakharov.gzwhisper`
- installer: `build/GZWhisper-Installer-1.5.0.dmg`

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

Output: `build/GZWhisper-macOS-1.5.0.zip`

The ZIP now includes:
- `GZWhisper.app`
- `Install_Instructions.txt`
- `Run_If_Blocked.txt`
- `Enable_GZWhisper.command`

### 4) Build DMG installer

```bash
./scripts/build_dmg.sh
```

Output: `build/GZWhisper-Installer-1.5.0.dmg`

# First run (all platforms)

1. Open the app.
2. Click **Download model** (or connect an existing local model folder).
3. Wait for one-time environment setup and dependency install.
4. Pick an audio/video file and run transcription.

## Notes

- For macOS builds with the validated embedded wheelhouse, Python dependencies install fully offline.
- Internet is needed only for the first-time model download.
- Once the model is local, transcription can run offline.
- Linux video transcription requires `ffmpeg`.
- Windows video transcription requires `ffmpeg.exe` (next to app or in `PATH`).

## Project layout

- `Sources/` — macOS app source code.
- `linux/` — Linux app source code.
- `Resources/transcription_worker.py` — shared worker for model download/validation/transcription.
- `scripts/` — build, package, install, uninstall scripts.

## Changelog

### 2026-08-25 (v1.5.0, build 250826)

- Compacted the macOS header, model controls, history rows, transcription controls, result actions, and footer to provide more room for transcripts.
- Replaced the persistent model card with a compact status menu that expands only for setup, progress, or runtime errors.
- Locked the Python 3.12 Apple Silicon wheelhouse for macOS 12+, including the previously missing `sympy` dependency.
- Added a release-time clean-venv check that resolves and installs the complete dependency set without network access.
- Improved dependency diagnostics so offline-wheelhouse and online-PyPI failures are reported separately.

### 2026-06-15 (v1.4.3, build 150626)

- Added persistent queue controls: run selected history items, reorder queued files, pause after the current item, resume, skip the current item, remove a queued item, or clear the waiting queue.
- Added a clearer error when a video file has no audio track.
- Updated macOS app version and packaging defaults to `v1.4.3`.

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
