<p align="center">
  <img src="Resources/AppIcon.png" width="96" alt="GZ Whisper Legacy icon">
</p>

<h1 align="center">GZ Whisper Legacy</h1>

<p align="center">
  Private, local-first transcription for macOS.<br>
  Maintenance only: fixes for user-reported bugs.
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/github/v/release/globa-me/GZWhisper?style=flat-square&color=172554">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-172554?style=flat-square&logo=apple">
  <img alt="Apple Silicon and Intel" src="https://img.shields.io/badge/Mac-arm64%20%7C%20x86__64-0f766e?style=flat-square">
  <img alt="Local first" src="https://img.shields.io/badge/privacy-local--first-0f766e?style=flat-square">
</p>

<p align="center">
  <a href="https://github.com/globa-me/GZWhisper/releases/download/v1.5.5/GZWhisper-Legacy-Installer-1.5.5-Apple-Silicon.dmg"><strong>Apple Silicon DMG</strong></a>
  ·
  <a href="https://github.com/globa-me/GZWhisper/releases/download/v1.5.5/GZWhisper-Legacy-Installer-1.5.5-Intel.dmg"><strong>Intel DMG</strong></a>
  ·
  <a href="https://github.com/globa-me/GZWhisper/releases/download/v1.5.5/GZWhisper-Legacy-macOS-1.5.5.zip"><strong>Apple Silicon ZIP</strong></a>
  ·
  <a href="docs/GZWHISPER_PRODUCT_FUNCTIONALITY_RU.md">Описание на русском</a>
</p>

<p align="center">
  <strong>Support independent GZ Apps development</strong><br>
  Support GZ Apps development and maintenance updates.
</p>

<p align="center">
  <a href="https://www.patreon.com/c/globa_me"><img alt="Support on Patreon" src="https://img.shields.io/badge/Support_on-Patreon-FF424D?style=for-the-badge&logo=patreon&logoColor=white"></a>
  <a href="https://boosty.to/globa_me"><img alt="Support on Boosty" src="https://img.shields.io/badge/Support_on-Boosty-F15F2C?style=for-the-badge"></a>
</p>

<table>
  <tr>
    <td width="72%">
      <img src="docs/assets/gzwhisper-main.png" alt="GZ Whisper Legacy main window">
    </td>
    <td width="28%">
      <img src="docs/assets/gzwhisper-history-search.png" alt="GZ Whisper Legacy history search">
    </td>
  </tr>
</table>

## Maintenance status

As of 2026-10-09, this app is **GZ Whisper Legacy**. New feature development is frozen; future work is limited to fixes for user-reported bugs. Active development continues in the separate **GZ Whisper** app for iOS and macOS.

Current release: **v1.5.5 · build 270829** (2026-10-10). [Legacy update notes](docs/RELEASE_NOTES_1.5.5_RU.md). Earlier releases remain available under the original GZWhisper name.

The Legacy update retains the existing bundle ID, history, models, settings, and data folders. New GZ Whisper has its own application identity. The screenshots above show the earlier interface under its original name.

## Highlights

- Local transcription with a downloadable catalog of Whisper-compatible models from Hugging Face.
- Apple Silicon/Intel-aware model recommendations, approximate RAM and disk requirements, switching, and removal.
- Intel-safe retry and explicit diagnostics when the native transcription worker is terminated unexpectedly.
- Audio, video, microphone, system audio, or system audio + microphone.
- Pause/resume recording and automatic recovery after interrupted sessions.
- Searchable history with original recording dates, optional transcription-date sorting, queue, rename, delete with undo, and quick actions.
- Draft edits save automatically; queued imports survive restart; history rows work with the keyboard and VoiceOver.
- TXT and JSON export, including multi-select ZIP archives with one file per transcript.
- Russian, English, and Chinese interface.

Your media, recordings, models, and transcripts stay on your Mac. Network access is only needed to download a model.

## Install on macOS

Current release: **GZ Whisper Legacy v1.5.5 · build 270829**.

[v1.5.5 change notes](docs/RELEASE_NOTES_1.5.5_RU.md)

Requirements for the architecture-specific builds: Apple Silicon or 64-bit Intel Mac, macOS 14 or later. Both macOS 14 and macOS 15 are supported.

1. Download the [Apple Silicon DMG](https://github.com/globa-me/GZWhisper/releases/download/v1.5.5/GZWhisper-Legacy-Installer-1.5.5-Apple-Silicon.dmg), [Intel DMG](https://github.com/globa-me/GZWhisper/releases/download/v1.5.5/GZWhisper-Legacy-Installer-1.5.5-Intel.dmg), or [Apple Silicon ZIP](https://github.com/globa-me/GZWhisper/releases/download/v1.5.5/GZWhisper-Legacy-macOS-1.5.5.zip).
2. When updating, quit the previous app and back up `GZWhisper.app` before moving it out of `/Applications`. Keep your existing data folders.
3. Move `GZ Whisper Legacy.app` to `/Applications`.
4. Open Legacy and allow microphone or system-audio access when needed. Do not reset existing privacy permissions.

<details>
<summary><strong>If macOS blocks the app</strong></summary>

Control-click `GZ Whisper Legacy.app` and choose **Open**. If macOS still blocks it, open **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper globally.

</details>

## Build from source

```bash
git clone https://github.com/globa-me/GZWhisper.git
cd GZWhisper
PYTHON_BIN="$(brew --prefix python@3.12)/bin/python3.12" ./scripts/prepare_embedded_python.sh
./scripts/build_app.sh
open "build/GZ Whisper Legacy.app"
```

The macOS build uses the bundled Python runtime and offline wheelhouse. It creates `build/GZ Whisper Legacy.app`; package defaults are `build/GZWhisper-Legacy-macOS-1.5.5.zip` and `build/GZWhisper-Legacy-Installer-1.5.5.dmg`. For a Legacy update, quit the original app, back it up, and keep only `GZ Whisper Legacy.app` in `/Applications`. Release packages:

```bash
./scripts/package_zip.sh
./scripts/build_dmg.sh
```

To build, sign, notarize, and staple separate Apple Silicon and Intel DMGs:

```bash
./scripts/build_macos_variants.sh
```

The resulting artifacts are written to `build/releases/Apple-Silicon/` and `build/releases/Intel/`. Building locally does not publish or replace the GitHub release downloads above.

## Platform status

| Platform | Status | Source / guide |
|---|---|---|
| macOS arm64 | Stable, tested | `Sources/` |
| macOS x86_64 | Build verified through Rosetta x86_64 execution; physical Intel smoke-test recommended | `Sources/` |
| Linux | Experimental | `linux/gzwhisper_linux.py` |
| Windows portable | Experimental | [Windows guide](docs/WINDOWS_PORTABLE.md) |

## Project map

- `Sources/` — SwiftUI macOS application.
- `Resources/transcription_worker.py` — shared transcription worker.
- `scripts/` — build, packaging, and safety tools.
- [`docs/GZWHISPER_PRODUCT_FUNCTIONALITY_RU.md`](docs/GZWHISPER_PRODUCT_FUNCTIONALITY_RU.md) — full product functionality in Russian.

## Release checks

```bash
./scripts/check_repo_security.sh
./scripts/check_wheelhouse.sh
codesign --verify --deep --strict "build/GZ Whisper Legacy.app"
```

Built and maintained by [Gennadiy Zakharov](https://zakharov.asia/).

For Developer ID signing and notarized DMG builds, see [macOS distribution](docs/MACOS_DISTRIBUTION.md).
