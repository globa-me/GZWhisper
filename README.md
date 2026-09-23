<p align="center">
  <img src="Resources/AppIcon.png" width="96" alt="GZWhisper icon">
</p>

<h1 align="center">GZWhisper</h1>

<p align="center">
  Private, local-first transcription for macOS.
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/github/v/release/globa-me/GZWhisper?style=flat-square&color=172554">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-172554?style=flat-square&logo=apple">
  <img alt="Apple Silicon and Intel" src="https://img.shields.io/badge/Mac-arm64%20%7C%20x86__64-0f766e?style=flat-square">
  <img alt="Local first" src="https://img.shields.io/badge/privacy-local--first-0f766e?style=flat-square">
</p>

<p align="center">
  <a href="https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-Installer-1.5.3-Apple-Silicon.dmg"><strong>Apple Silicon DMG</strong></a>
  ·
  <a href="https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-Installer-1.5.3-Intel.dmg"><strong>Intel DMG</strong></a>
  ·
  <a href="https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-macOS-1.5.3.zip"><strong>Apple Silicon ZIP</strong></a>
  ·
  <a href="docs/GZWHISPER_PRODUCT_FUNCTIONALITY_RU.md">Описание на русском</a>
</p>

<p align="center">
  <strong>Support independent GZ Apps development</strong><br>
  Get ready-to-run builds, updates, and member posts while helping me improve this project.
</p>

<p align="center">
  <a href="https://www.patreon.com/c/globa_me"><img alt="Support on Patreon" src="https://img.shields.io/badge/Support_on-Patreon-FF424D?style=for-the-badge&logo=patreon&logoColor=white"></a>
  <a href="https://boosty.to/globa_me"><img alt="Support on Boosty" src="https://img.shields.io/badge/Support_on-Boosty-F15F2C?style=for-the-badge"></a>
</p>

<table>
  <tr>
    <td width="72%">
      <img src="docs/assets/gzwhisper-main.png" alt="GZWhisper main window">
    </td>
    <td width="28%">
      <img src="docs/assets/gzwhisper-history-search.png" alt="GZWhisper history search">
    </td>
  </tr>
</table>

## Highlights

- Local transcription with a downloadable catalog of Whisper-compatible models from Hugging Face.
- Apple Silicon/Intel-aware model recommendations, approximate RAM and disk requirements, switching, and removal.
- Intel-safe retry and explicit diagnostics when the native transcription worker is terminated unexpectedly.
- Audio, video, microphone, system audio, or system audio + microphone.
- Pause/resume recording and automatic recovery after interrupted sessions.
- Searchable history, transcription queue, rename, delete with undo, and quick actions.
- Draft edits save automatically; queued imports survive restart; history rows work with the keyboard and VoiceOver.
- TXT and JSON export, including multi-select ZIP archives with one file per transcript.
- Russian, English, and Chinese interface.

Your media, recordings, models, and transcripts stay on your Mac. Network access is only needed to download a model.

## Install on macOS

Current release: **v1.5.3 · build 270827**.

[v1.5.3 change notes](docs/RELEASE_NOTES_1.5.3_RU.md)

Requirements for the architecture-specific builds: Apple Silicon or 64-bit Intel Mac, macOS 14 or later. Both macOS 14 and macOS 15 are supported.

1. Download the [Apple Silicon DMG](https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-Installer-1.5.3-Apple-Silicon.dmg), [Intel DMG](https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-Installer-1.5.3-Intel.dmg), or [Apple Silicon ZIP](https://github.com/globa-me/GZWhisper/releases/latest/download/GZWhisper-macOS-1.5.3.zip).
2. Move `GZWhisper.app` to `/Applications`.
3. Open the app and allow microphone or system-audio access when needed.

<details>
<summary><strong>If macOS blocks the app</strong></summary>

Control-click `GZWhisper.app` and choose **Open**. If macOS still blocks it, open **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper globally.

</details>

## Build from source

```bash
git clone https://github.com/globa-me/GZWhisper.git
cd GZWhisper
PYTHON_BIN="$(brew --prefix python@3.12)/bin/python3.12" ./scripts/prepare_embedded_python.sh
./scripts/build_app.sh
open build/GZWhisper.app
```

The macOS build uses the bundled Python runtime and offline wheelhouse. Release packages:

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
codesign --verify --deep --strict build/GZWhisper.app
```

Built and maintained by [Gennadiy Zakharov](https://zakharov.asia/).

For Developer ID signing and notarized DMG builds, see [macOS distribution](docs/MACOS_DISTRIBUTION.md).
