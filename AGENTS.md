# AI Agent Notes

This repository contains GZWhisper, a local-first desktop transcription app.

## Current State

- Current source version: `v1.5.2`, build `270826`.
- Version `v1.5.2` fixes duplicate history-deletion status text and makes interrupted-recording recovery automatic, including sleep/wake and unexpected capture interruptions. It also includes the compact queue/recording UI, larger history metadata rows, in-list animated history search, and the `238x90` recording HUD developed after `v1.5.1`.
- History search is debounced and runs through an actor-backed normalized index, keeping transcript reads, file metadata checks, and full-text matching off the main actor. Search results are computed once per settled query rather than repeatedly during SwiftUI rendering.
- History row hover state is local to each row wrapper, so scrolling across the pointer no longer invalidates the entire `ContentView`; repeated row metadata formatting is also avoided.
- Recording can now start while a transcription queue is active. The footer derives separate live transcription and recording summaries and displays both with a divider.
- History deletion now has a 15-second single-item undo action. Files remain in place during the undo window and are moved to the macOS Trash when it expires; imported source media is still never deleted unless it is an app-created recording referenced by `audioPath`.
- Interrupted recordings are finalized automatically when macOS goes to sleep, after wake as a fallback, and when ScreenCaptureKit or the microphone capture session reports an unexpected stop. Recording uses fragmented M4A staging files for crash recovery; recovery accepts only readable audio and preserves a surviving system or microphone track if a two-track merge fails. Finalization always clears the live recording UI so a new recording is not blocked.
- The footer shows history-deletion feedback only in the dedicated 15-second undo control, avoiding a duplicate copy in the general status area.
- macOS builds now reject revoked code-signing identities during automatic selection. Python subprocesses also set `PYTHONDONTWRITEBYTECODE=1` so the embedded runtime cannot add `__pycache__` files inside a signed app bundle and invalidate its resource seal.
- Primary supported platform: macOS on Apple Silicon (`arm64`).
- Linux and Windows portable variants exist, but macOS is the priority and the only stable/tested target.
- The current macOS app bundle is `build/GZWhisper.app`.
- Release package defaults are:
  - `build/GZWhisper-macOS-1.5.2.zip`
  - `build/GZWhisper-Installer-1.5.2.dmg`

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
