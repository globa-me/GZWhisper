# AI Agent Notes

This repository contains GZWhisper, a local-first desktop transcription app.

## Current State

- Current source and published version: `v1.5.3`, build `270827`. README download links select the architecture-specific 1.5.3 DMGs and Apple Silicon ZIP.
- The Apple Silicon `v1.5.3` app, ZIP, and DMG were built on 2026-09-23. Apple accepted app submission `e9f36619-47a3-4686-beef-71093726ef42` and DMG submission `c08e4ebf-4f62-45da-a42b-44fe15ef89fc`; both tickets were stapled. Gatekeeper accepts the app, DMG, extracted ZIP app, and mounted DMG app as `Notarized Developer ID`. Separate Apple Silicon and Intel apps/DMGs were also built, notarized, and verified from mounted images; IDs and hashes are in `docs/MACOS_DISTRIBUTION.md`. The notarytool Keychain profile `GZWhisper` is available; an earlier unavailable-profile result was transient. Swift typechecking passed for arm64 and x86_64; isolated history tests passed for queued imports, TXT edit/segment invalidation, damaged JSON salvage, and undo recovery after restart. The installed `/Applications/GZWhisper.app` was updated from 1.5.2 to the notarized 1.5.3 Apple Silicon variant; its previous app bundle is backed up under `build/installed-backup/`. The main UI opened with all 210 existing history items, and a system + microphone recording started without a new macOS permission prompt. The test recording was deleted through the app. Physical Intel hardware validation remains recommended. See `docs/RELEASE_NOTES_1.5.3_RU.md` and `docs/MACOS_DISTRIBUTION.md`.
- Version `v1.5.3` saves transcript edits to the original TXT automatically and before switching items, export, or window close; manual edits invalidate stored segment timestamps. History JSON now retains unedited segment timestamps and the model path used for each result. Imported queue items survive restart; a malformed history file is backed up and individually recoverable entries are loaded. Pending history deletions use an on-disk journal so expiration is resolved after restart. The main UI uses a single window to avoid concurrent history writers, history rows are keyboard/VoiceOver accessible, and the result pane has state-specific empty messages. Recording startup is guarded against repeated clicks. macOS build defaults now target 14.0.
- To preserve ScreenCaptureKit TCC grants across releases, `build_app.sh` now requires a stable signed identity by default and never silently falls back to ad hoc signing. `check_release_identity.sh` gates ZIP/DMG/notarization on the fixed bundle ID, Team ID, valid Developer ID signature, and the installed app's designated requirement when present. The installed 1.5.2 app and local 1.5.3 app had identical designated requirements. Explicit ad hoc builds remain possible with `SIGNING_IDENTITY=-` for isolated testing only. Apple documentation says a change from ad hoc or another signing identity can require one fresh grant; do not reset TCC permissions as part of updates.
- The macOS app now has a multi-model library. Users can download Tiny, Base, Small, Large v3 Turbo, or Large v3; see architecture/RAM-aware recommendations with separate minimum/recommended memory; keep multiple models; switch the active model; remove app-downloaded models; and link external CTranslate2 models. `selected_model.json` remains the active pointer, while `installed_models.json` is the persisted registry and automatically imports the legacy selected model. New app-owned download directories receive a `.gzwhisper-model.json` ownership marker; recursive deletion requires its token to match the registry, while legacy or external folders are only unlinked.
- Native transcription worker failures can no longer produce an empty history error or be hidden by `Queue completed`. `ProcessResult` preserves termination reason/signal; Intel signal crashes get one bounded retry with generic ISA, MKL/packed GEMM disabled, two CPU threads, and `beam_size=1`. The bundled locked requirements file is copied into the app and persistent venv versions are checked against it, so an importable but stale CTranslate2/faster-whisper environment is upgraded after app updates.
- Each transcription attempt writes a privacy-conscious persistent stage log under `Application Support/GZWhisper/Worker Logs`. It records environment/model/file metadata, worker milestones, exception type, termination reason/status, and a bounded stderr tail, but never transcript text. The newest two logs are embedded in the copied diagnostic report and only the eight newest files are retained.
- Version `v1.5.2` fixes duplicate history-deletion status text and makes interrupted-recording recovery automatic, including sleep/wake and unexpected capture interruptions. It also includes the compact queue/recording UI, larger history metadata rows, in-list animated history search, and the `238x90` recording HUD developed after `v1.5.1`.
- History search is debounced and runs through an actor-backed normalized index, keeping transcript reads, file metadata checks, and full-text matching off the main actor. Search results are computed once per settled query rather than repeatedly during SwiftUI rendering.
- History row hover state is local to each row wrapper, so scrolling across the pointer no longer invalidates the entire `ContentView`; repeated row metadata formatting is also avoided. Hover actions remain mounted in a trailing overlay and only change opacity and hit-testing, preventing both row relayout/tracking-area churn and invisible action controls from squeezing history metadata.
- Recording can now start while a transcription queue is active. The footer derives separate live transcription and recording summaries and displays both with a divider.
- History deletion now has a 15-second single-item undo action. Files remain in place during the undo window and are moved to the macOS Trash when it expires; imported source media is still never deleted unless it is an app-created recording referenced by `audioPath`.
- Interrupted recordings are finalized automatically when macOS goes to sleep, after wake as a fallback, and when ScreenCaptureKit or the microphone capture session reports an unexpected stop. Recording uses fragmented M4A staging files for crash recovery; recovery accepts only readable audio and preserves a surviving system or microphone track if a two-track merge fails. Finalization always clears the live recording UI so a new recording is not blocked.
- The footer shows history-deletion feedback only in the dedicated 15-second undo control, avoiding a duplicate copy in the general status area.
- macOS builds now reject revoked code-signing identities during automatic selection. Python subprocesses also set `PYTHONDONTWRITEBYTECODE=1` so the embedded runtime cannot add `__pycache__` files inside a signed app bundle and invalidate its resource seal.
- TXT and JSON export dialogs derive their suggested filename from the open history item's current display name, including user renames. Original media extensions are removed for unrenamed items, and unsafe filename characters are sanitized.
- Completed history items support a separate multi-select export mode. Selected transcripts are exported as one ZIP containing separate TXT or JSON files; visible search results can be selected at once, and duplicate display names receive numeric suffixes.
- The repository README is intentionally concise and uses sanitized demo screenshots from `docs/assets/gzwhisper-main.png` and `docs/assets/gzwhisper-history-search.png`; do not replace them with captures containing real transcript or history data.
- `docs/GZWHISPER_PRODUCT_FUNCTIONALITY_RU.md` is the maintained Russian product-functionality baseline for competitor research. It describes the full macOS feature set, Linux/Windows differences, current limitations, local data handling, and a ready-to-use deep-research prompt; update it when user-facing capabilities materially change. Regenerate its shareable DOCX with `scripts/build_product_functionality_docx.py`.
- Primary supported platform: macOS on Apple Silicon (`arm64`) and Intel (`x86_64`). Architecture-specific builds are produced separately with a macOS 14.0 deployment target, covering macOS 14 and macOS 15.
- Linux and Windows portable variants exist, but macOS is the priority and the only stable/tested target. The Intel build has been cross-compiled and exercised through Rosetta x86_64 execution; final hardware validation should still be repeated on a physical Intel Mac when one is available.
- The current macOS app bundle is `build/GZWhisper.app`.
- Release package defaults are:
  - `build/GZWhisper-macOS-1.5.3.zip`
  - `build/GZWhisper-Installer-1.5.3.dmg`
- Architecture-specific release artifacts are:
  - `build/releases/Apple-Silicon/GZWhisper-Installer-1.5.3-Apple-Silicon.dmg`
  - `build/releases/Intel/GZWhisper-Installer-1.5.3-Intel.dmg`

## Project Layout

- `Sources/` - SwiftUI macOS app source.
- `Resources/transcription_worker.py` - shared Python worker for model download, validation, and transcription.
- `Resources/python/` - preferred embedded Python runtime, currently Python 3.12.
- `Resources/Python.framework/` - legacy/fallback embedded Python framework, currently Python 3.9.
- `Resources/wheelhouse/` - offline Python dependency wheels for the embedded runtime.
- `Resources/requirements-macos.txt` - locked Python 3.12 dependency set used by the separate macOS Apple Silicon and Intel wheelhouses.
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
./scripts/build_macos_variants.sh
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

## Distribution preparation (2026-09-09)

- Developer ID Application identity is installed for team `BN3D9H4C7J`; notarization credentials are validated in Keychain profile `GZWhisper`.
- `scripts/sign_app.py` signs native code inside wheel archives and regenerates RECORD hashes, then signs embedded Mach-O files, nested bundles and the app. Source wheelhouse is unchanged. Python uses `Resources/Python.entitlements` to load native dependencies in the external venv.
- `scripts/notarize_release.sh` notarizes/staples the app before creating and notarizing the DMG. See `docs/MACOS_DISTRIBUTION.md` for the repeatable release workflow.
- `scripts/build_dmg.sh` no longer packages Gatekeeper bypass files/text; with a notary profile it signs and verifies the final DMG.
- Current app notarization accepted: `e994ad23-63cf-432a-a004-700a90a5c6b5`; ticket stapled and Gatekeeper reports `Notarized Developer ID`. Signed wheels passed clean offline installation/import tests. Current DMG submission `8314e95f-b1d0-4ba4-9278-c8203cb05cfc` also accepted; DMG ticket stapled/validated and Gatekeeper accepted it. App inside the mounted DMG also passed signature, ticket and Gatekeeper checks. The installed `/Applications/GZWhisper.app` was replaced with this build; existing published downloads remain unchanged.

## Dual-architecture distribution (2026-09-11)

- `scripts/build_app.sh`, `scripts/check_wheelhouse.sh`, `scripts/prepare_embedded_python.sh`, `scripts/build_dmg.sh`, and `scripts/notarize_release.sh` accept architecture/build-directory overrides. `scripts/build_macos_variants.sh` drives the complete two-build release.
- Both variants use deployment target macOS 14.0. The Intel variant bundles relocatable x86_64 Python 3.12.11 from `python-build-standalone` plus a separately resolved x86_64 wheelhouse; the download is checksum-pinned in the script.
- Clean offline dependency installation and imports passed for both architectures. The x86_64 Python runtime and app executable were run under Rosetta; the Intel GUI reached its running state without an early crash.
- Apple Silicon app/DMG notarization submissions: `e045493a-3f5a-4270-bbc4-0b1f6111c2c1` / `0eb75fb3-c7ca-4901-a3a8-ea772f0a1889` — Accepted.
- Intel app/DMG notarization submissions: `022f576c-037a-4aba-933f-a5f8ad8e2a4e` / `fb1dd7b1-b61e-4c32-97b5-57c4521ebf33` — Accepted.
- Both mounted DMGs contain the correct single-architecture app and Python runtime, and both pass strict signature, stapler, and Gatekeeper checks. Existing published downloads remain unchanged.
