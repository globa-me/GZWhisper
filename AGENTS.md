# AI Agent Notes

This repository contains GZWhisper, a local-first desktop transcription app.

## Current State

- Current source version: `v1.5.0`, build `250826`.
- Version `v1.5.0` compacts the macOS workspace and hardens fully offline Python dependency installation.
- Primary supported platform: macOS on Apple Silicon (`arm64`).
- Linux and Windows portable variants exist, but macOS is the priority and the only stable/tested target.
- The current macOS app bundle is `build/GZWhisper.app`.
- Release package defaults are:
  - `build/GZWhisper-macOS-1.5.0.zip`
  - `build/GZWhisper-Installer-1.5.0.dmg`

## Project Layout

- `Sources/` - SwiftUI macOS app source.
- `Resources/transcription_worker.py` - shared Python worker for model download, validation, and transcription.
- `Resources/python/` - preferred embedded Python runtime, currently Python 3.12.
- `Resources/Python.framework/` - legacy/fallback embedded Python framework, currently Python 3.9.
- `Resources/wheelhouse/` - offline Python dependency wheels for the embedded runtime.
- `Resources/requirements-macos.txt` - locked Python 3.12 dependency set for macOS 12+ Apple Silicon builds.
- `Resources/GZWhisper.entitlements` - app signing entitlements.
- `linux/gzwhisper_linux.py` - Linux app and Windows portable source.
- `scripts/` - build, packaging, install, and safety scripts.
- `docs/WINDOWS_PORTABLE.md` - Windows portable notes.

## Common Commands

```bash
./scripts/check_repo_security.sh
./scripts/check_wheelhouse.sh
./scripts/make_icon.sh
./scripts/build_app.sh
./scripts/package_zip.sh
./scripts/build_dmg.sh
```

If embedded runtime assets are missing:

```bash
PYTHON_BIN=/opt/homebrew/bin/python3 ./scripts/prepare_embedded_python.sh
```

## Cleanup Rules

- `build/` is generated and ignored by git. Keep only the current local build artifacts there when cleaning.
- Do not commit `build/`, embedded runtime folders, wheelhouse files, `.DS_Store`, `__pycache__/`, or `*.pyc`.
- Keep `README.md` and this file updated when version defaults or packaging commands change.
- Avoid changing bundle id `com.gzakharov.gzwhisper` unless intentionally creating a side-by-side install.
