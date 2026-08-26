# AI Agent Notes

This repository contains GZWhisper, a local-first desktop transcription app.

## Current State

- Current source version: `v1.5.1`, build `2508261`.
- Version `v1.5.1` adds responsive wide/compact SwiftUI layouts so controls wrap cleanly instead of clipping in narrow windows. It preserves the existing support directory and transcript history format.
- Unreleased macOS work after `v1.5.1` further compacts the queue and recording controls, enlarges history metadata rows, adds an in-list animated history search, and reduces the recording HUD to `238x90` points.
- History search is debounced and runs through an actor-backed normalized index, keeping transcript reads, file metadata checks, and full-text matching off the main actor. Search results are computed once per settled query rather than repeatedly during SwiftUI rendering.
- History row hover state is local to each row wrapper, so scrolling across the pointer no longer invalidates the entire `ContentView`; repeated row metadata formatting is also avoided.
- Recording can now start while a transcription queue is active. The footer derives separate live transcription and recording summaries and displays both with a divider.
- History deletion now has a 15-second single-item undo action. Files remain in place during the undo window and are moved to the macOS Trash when it expires; imported source media is still never deleted unless it is an app-created recording referenced by `audioPath`.
- Primary supported platform: macOS on Apple Silicon (`arm64`).
- Linux and Windows portable variants exist, but macOS is the priority and the only stable/tested target.
- The current macOS app bundle is `build/GZWhisper.app`.
- Release package defaults are:
  - `build/GZWhisper-macOS-1.5.1.zip`
  - `build/GZWhisper-Installer-1.5.1.dmg`

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
