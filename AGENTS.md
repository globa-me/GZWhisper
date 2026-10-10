# AI Agent Notes

This repository contains **GZ Whisper Legacy**, the original local-first desktop transcription app (formerly GZWhisper).

## Maintenance policy — 2026-10-09

- New feature development is frozen. Only fixes for user-reported bugs are authorized by the standing product direction; do not resume feature roadmaps or diarization experiments here without a new explicit user request.
- Active feature development belongs to the separate GZ Whisper for iOS and macOS in `../GZWhisper-iOS`. Do not modify that project as part of a Legacy task. Its installed Mac app is `/Applications/GZ Whisper Mac.app` (a symlink to that project's build); its bundle ID is `com.gzakharov.gzwhisper.ios`.
- Preserve Legacy's bundle ID `com.gzakharov.gzwhisper`, Team ID `BN3D9H4C7J`, executable/module `GZWhisper`, preferences and `Documents/GZWhisper` / `Application Support/GZWhisper` paths. Rename visible branding and app/package filenames only. Do not reset TCC or migrate/delete user data for a rename.
- Default Developer ID identity is the G2 SHA-1 `6E99F92E9A1BA1273CD084FAFE940A7280DB0A30`; notarization profile is `GZB-notary`. Identity gates compare with the renamed installed app, falling back to `/Applications/GZWhisper.app` during the initial upgrade.


## Current State

- GitHub release `v1.5.5` published on 2026-10-10: Apple Silicon DMG/ZIP, generic arm64 DMG, Intel DMG and checksums. Repository description/README identify GZ Whisper Legacy and maintenance-only support. Intel app `570d3bab-cd24-4499-920d-a41cf9c5947c` and DMG `4f9cc2b5-9e92-48e2-b706-34fcda0a86ce` are Accepted and stapled; mounted Intel app passed strict signature, ticket and Gatekeeper checks, and its app/Python are x86_64. Signed Intel wheels passed clean offline imports under Rosetta. Hashes, limitations and reproduction commands are in `docs/MACOS_DISTRIBUTION.md`.

- App and generic Apple Silicon ZIP/DMG 1.5.5 are built and notarized locally. Apple accepted app `8c61e5fe-9f35-46ab-9f00-180942f0b4bb` and DMG `0f110d32-0d5d-4f84-aed4-81f978644465`; both tickets are stapled. Gatekeeper accepts the app, DMG, extracted ZIP app and mounted DMG app. Hashes and commands are in `docs/MACOS_DISTRIBUTION.md`. These artifacts were prepared locally on 2026-10-09; publication is recorded in the release entry below.
- Installed on 2026-10-09: `/Applications/GZ Whisper Legacy.app`; main window and app menu show the Legacy name, the existing Dock shortcut points there, and all 136 history entries and model pointers are unchanged. Original 1.5.4 app, history/model snapshots and Dock preferences are backed up in ignored `build/installed-backup/legacy-transition-2026-10-09/`. The separate new GZ Whisper app was not modified.
- Current source/release version: **v1.5.5, build 270829**, renamed to GZ Whisper Legacy; release date 2026-10-10. The already-present timeout fix, retranscription and manual dialogue marker are included in this transition build; future features are frozen. See `docs/RELEASE_NOTES_1.5.5_RU.md` and the current section of `docs/MACOS_DISTRIBUTION.md` for actual validation/install results. GitHub release: `https://github.com/globa-me/GZWhisper/releases/tag/v1.5.5`. The repository remains `globa-me/GZWhisper` to preserve existing links; its description now identifies Legacy and maintenance-only support.

- Fix included in `v1.5.5` after published `v1.5.4`: a reported Apple Silicon worker remained at `model_load_started` for over seven minutes while loading Large v3 Turbo. Signal 15 in the supplied log indicates process termination after the stall, not proof of a native crash; the source of that signal is unconfirmed. `Sources/WhisperEngine.swift` now shows a loading status, warns after 45 seconds, times out after five minutes, terminates the stuck worker, writes `model_load_timeout_seconds: 300`, and returns an error with actions to re-download the model or try Small/Base. `Sources/AppViewModel.swift` pauses the queue after this error, preserving remaining queued files. `Sources/GZWhisperApp.swift` shows loading messages during an active queue and the full error in the result pane. The worker emits only a stage event after model load, with no transcript content. This guards against indefinite stalls; the underlying cause on the user's Mac is not yet confirmed. Ask for model file metadata and free memory/disk space if investigating that machine. Do not describe this source change as present in a published 1.5.4 build until released.
- Previously unreleased work included in `v1.5.5`: completed history items offer Retranscribe. It queues a separate result with the same source media while retaining the original transcript and edits; generated TXT names now include a short UUID suffix to prevent collisions. Pending deletion checks references from other history items before trashing shared app recordings. The editor also offers a persistent configurable dialogue marker (default `- `) inserted at the cursor with Cmd-Shift-M; speaker changes remain manual. `docs/GZWHISPER_PRODUCT_FUNCTIONALITY_RU.md` describes these working-tree features. Automatic speaker diarization is still absent; `docs/SPEAKER_DIARIZATION_PROPOSAL_RU.md` is an archived candidate architecture and validation reference; the Legacy feature is frozen. Do not add models to the runtime before validating accuracy and CPU/RAM cost on supported Macs.
- Previous published version: `v1.5.4`, build `270828`. This update fixes inline history rename keyboard handling and separates the original media date (`recordedAt`) from the transcription completion date (`transcribedAt`). History displays and defaults to sorting by the original date; the history header also offers persistent sorting by transcription date. Older entries are migrated and saved on load: app recording filenames provide the original Unix timestamp, otherwise file creation/modification metadata is used, with legacy `createdAt` as fallback. New transcriptions no longer overwrite `createdAt`. See `docs/RELEASE_NOTES_1.5.4_RU.md`.
- Earlier published version: `v1.5.3`, build `270827`. Its release remains available as a rollback reference.
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
- The local Apple Silicon app bundle is `build/GZ Whisper Legacy.app`; architecture-specific release bundles are under `build/releases/`.
- Release package defaults are:
  - `build/GZWhisper-Legacy-macOS-1.5.5.zip`
  - `build/GZWhisper-Legacy-Installer-1.5.5.dmg`
- Architecture-specific release artifact paths are (Apple Silicon DMG is a byte-identical copy of the generic notarized arm64 installer; Intel is built separately):
  - `build/releases/Apple-Silicon/GZWhisper-Legacy-Installer-1.5.5-Apple-Silicon.dmg`
  - `build/releases/Intel/GZWhisper-Legacy-Installer-1.5.5-Intel.dmg`

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
