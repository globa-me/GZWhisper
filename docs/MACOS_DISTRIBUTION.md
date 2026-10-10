# Developer ID distribution

Use the existing G2 Developer ID Application certificate (SHA-1 `6E99F92E9A1BA1273CD084FAFE940A7280DB0A30`) with its Keychain private key, team `BN3D9H4C7J`. The default notarization Keychain profile is `GZB-notary`. Do not export credentials or store secrets in this repository.

```bash
ALLOW_APPLE_DEVELOPMENT_FALLBACK=0 ./scripts/build_app.sh
./scripts/notarize_release.sh
```

For separate macOS 14+ Apple Silicon and Intel releases, use the complete workflow:

```bash
./scripts/build_macos_variants.sh
```

The script checksum-verifies a relocatable x86_64 Python 3.12 runtime, resolves a
separate Intel wheelhouse, runs clean offline imports for each architecture, and
then signs, notarizes and staples each app and DMG independently.

The release script requires Developer ID signing, notarizes and staples the app,
then builds, signs, notarizes and staples the DMG. Both artifacts must pass
Gatekeeper assessment before distribution. A timeout is not rejection: inspect
submission status with `xcrun notarytool info ID --keychain-profile GZB-notary` and
retrieve errors with `xcrun notarytool log ID --keychain-profile GZB-notary`.

`sign_app.py` signs native binaries inside bundled wheels, regenerates their
RECORD hashes, signs embedded Mach-O files and nested bundles inside-out, and
finally seals the app. Only build copies of wheels are modified. Python permits
loading third-party native libraries from its external venv; the main app does
not receive that exception. Keep bytecode writes disabled inside the bundle.

DMGs contain the app and Applications shortcut. ZIP archives contain the app and
install instructions. Neither package includes a Gatekeeper bypass tool. Existing
public release downloads are not replaced by building a new local release.

## GZ Whisper Legacy 1.5.5 GitHub release — 2026-10-10

- Release: `https://github.com/globa-me/GZWhisper/releases/tag/v1.5.5`; source version `1.5.5`, build `270829`. The GitHub description and README identify Legacy and its maintenance-only policy. The repository URL is retained to preserve existing links. This is a separate product from the new GZ Whisper for iOS/macOS.
- Apple Silicon assets reuse the already-notarized 2026-10-09 app, ZIP and generic DMG without modifying or re-signing them. `build/releases/Apple-Silicon/GZWhisper-Legacy-Installer-1.5.5-Apple-Silicon.dmg` is a byte-identical copy of the generic arm64 DMG, SHA-256 `866bb02b351099d65b91aac3b173a15888eb4f4d92096605606f9e186d745ec7`; stapler and Gatekeeper passed on the copy.
- Intel was rebuilt separately from current source with macOS 14.0 deployment target, G2 Developer ID, Hardened Runtime, secure timestamps, embedded x86_64 Python 3.12 and locked Intel wheelhouse. Runtime/wheel sources were reused from the previous signed `build/releases/Intel/GZWhisper.app` without modifying that original bundle. Clean offline installation/imports passed under Rosetta; physical Intel hardware and recording were not tested in this publication task.
- Intel app submission `570d3bab-cd24-4499-920d-a41cf9c5947c`: **Accepted**. Ticket stapled/validated, strict signature and Gatekeeper passed (`Notarized Developer ID`). The bundle/executable names are GZ Whisper Legacy / GZWhisper, bundle ID remains `com.gzakharov.gzwhisper`, executable architecture is x86_64. Profile: `GZB-notary`.
- Intel DMG submission `4f9cc2b5-9e92-48e2-b706-34fcda0a86ce`: **Accepted**. Ticket stapled/validated and Gatekeeper passed. The app inside the mounted read-only DMG passed strict signature, stapler and Gatekeeper checks; both its app executable and Python runtime are x86_64, and its product name/version are GZ Whisper Legacy 1.5.5.
- Signed Intel wheels also passed a separate clean offline installation/import check under Rosetta with `PYTHONDONTWRITEBYTECODE=1`; the notarized bundle retained its valid resource seal. Intel DMG SHA-256: `54c5b8ae554c05d2d1cce559fe11d6e78749383de3203ba289a8778bf68f6eec`. The published `GZWhisper-Legacy-1.5.5-SHA256SUMS.txt` lists all four package names without local directory prefixes.
- Uploaded asset SHA-256 digests are checked against local packages before publication. The public release is marked latest; all README download links point to its versioned asset URLs. Historical 1.5.4 assets remain available.

Intel build reproduction using the existing 1.5.4 runtime assets (does not replace the installed app):

```bash
BUILD_DIR="$PWD/build/releases/Intel" TARGET_ARCH=x86_64 TARGET_PLATFORM=macosx_12_0_x86_64 \
  PYTHON_FRAMEWORK_SOURCE="$PWD/build/releases/Intel/no-python-framework" \
  PYTHON_RUNTIME_SOURCE="$PWD/build/releases/Intel/GZWhisper.app/Contents/Resources/python" \
  WHEELHOUSE_SOURCE="$PWD/build/releases/Intel/GZWhisper.app/Contents/Resources/wheelhouse" \
  ./scripts/build_app.sh
BUILD_DIR="$PWD/build/releases/Intel" APP_TITLE="GZ Whisper Legacy 1.5.5 (Intel)" \
  DMG_NAME=GZWhisper-Legacy-Installer-1.5.5-Intel VOL_NAME="GZ Whisper Legacy 1.5.5 Intel" \
  ./scripts/notarize_release.sh
```

For a clean runtime rebuild, use `./scripts/build_macos_variants.sh` instead. Publication uses an annotated `v1.5.5` tag, a draft GitHub release, verified uploaded asset digests, and finally marks the release public/latest. Linux and Windows renamed binaries are not published in this macOS release.

## GZ Whisper Legacy 1.5.5 local update — 2026-10-09

- Version `1.5.5`, build `270829`, Apple Silicon, macOS 14.0+. New Legacy branding; new features frozen, future work limited to user-reported bugs. At the time of this local update, public downloads remained 1.5.4.
- Built with the G2 Developer ID identity `6E99F92E9A1BA1273CD084FAFE940A7280DB0A30`, Hardened Runtime and secure timestamps. The bundle ID and designated requirement match the original installed app. No TCC reset or data migration was performed.
- App notarization `8c61e5fe-9f35-46ab-9f00-180942f0b4bb`: **Accepted**, ticket stapled/validated. Strict signature verification and Gatekeeper passed (`Notarized Developer ID`). Profile: `GZB-notary`.
- Installed at `/Applications/GZ Whisper Legacy.app`. Verified the window, header (`GZ Whisper Legacy 1.5.5`) and application menu. The original pinned Dock shortcut was updated to the renamed app. All 136 history entry IDs, history bytes and selected/installed model pointers remained unchanged after launch.
- Original installed app is backed up at `build/installed-backup/legacy-transition-2026-10-09/GZWhisper-1.5.4.app`, alongside history/model snapshots, original Dock preferences and rollback notes. The new `/Applications/GZ Whisper Mac.app` was not modified.
- Swift compilation/linking passed for arm64 and x86_64. The current signed arm64 bundle passed clean offline dependency installation/import checks. Intel was compiled for validation only; architecture-specific 1.5.5 apps/DMGs were not rebuilt. Recording/TCC and physical Intel hardware were not smoke-tested in this rename task.
- Previously prepared model-load timeout code required `@escaping` on its status callback to compile. The existing retranscription/manual dialogue-marker features are retained; the diarization proposal is archived.
- Final ZIP: `build/GZWhisper-Legacy-macOS-1.5.5.zip`, created after app stapling. The extracted app passed strict signature, stapler and Gatekeeper checks. SHA-256: `c99c98ec175ac830d0697cf7c99d30c6d99dc75102d2d1e9dce41a2858415c41`.
- Final DMG: `build/GZWhisper-Legacy-Installer-1.5.5.dmg`. Submission `0f110d32-0d5d-4f84-aed4-81f978644465`: **Accepted**, ticket stapled/validated, Gatekeeper passed. The app inside the mounted read-only DMG passed strict signature, stapler and Gatekeeper checks; its name is GZ Whisper Legacy and its executable is arm64. SHA-256: `866bb02b351099d65b91aac3b173a15888eb4f4d92096605606f9e186d745ec7`. Checksums are also saved in `build/GZWhisper-Legacy-1.5.5-SHA256SUMS.txt`. No publication was performed on 2026-10-09; subsequent GitHub publication is recorded above.

Reproduction (uses existing Keychain credentials; does not publish):

```bash
./scripts/build_app.sh
./scripts/notarize_release.sh
./scripts/package_zip.sh
./scripts/check_release_identity.sh "/Applications/GZ Whisper Legacy.app"
xcrun stapler validate "/Applications/GZ Whisper Legacy.app"
spctl --assess --type execute --verbose=4 "/Applications/GZ Whisper Legacy.app"
shasum -a 256 build/GZWhisper-Legacy-macOS-1.5.5.zip build/GZWhisper-Legacy-Installer-1.5.5.dmg
```

On the first transcription after the bundle rename, the engine recreates the external venv automatically if its bootstrap path references the former app. Data/model paths remain unchanged.

## v1.5.4 release — 2026-09-23

- Source version 1.5.4, build 270828, macOS 14.0+. Both architecture builds passed Swift typechecking and offline wheelhouse checks.
- Apple Silicon app/DMG notarization submissions: `5d7b3310-ae2b-4db2-942c-6087d8b2e0cf` / `407769bf-c7e0-45c6-ab23-b7f94870808e` — Accepted and stapled.
- Intel app/DMG notarization submissions: `6816e02d-2da4-4b22-878c-25caa9d32d55` / `8bb03240-34a6-4e65-b65b-cfcc05145bd4` — Accepted and stapled.
- Generic Apple Silicon DMG submission: `d36344b5-b78c-48ca-b30c-221fa3b8628b` — Accepted and stapled.
- Both mounted architecture-specific DMGs contained a single-architecture app; strict signature and Gatekeeper checks passed on the mounted apps. The extracted Apple Silicon ZIP app passed strict signature, stapler and Gatekeeper checks.
- The Apple Silicon app was installed at `/Applications/GZWhisper.app`; the previous app and pre-migration history JSON were backed up under ignored `build/installed-backup/`. All 212 history entries remained. The app saved original recording dates for 212 entries and completion dates for 206 completed entries. Rename with spaces, Enter and Escape was exercised in the UI; the test rename was reverted. The sort menu was exercised and returned to recording-date mode.
- Apple Silicon DMG SHA-256: `740b2b8ebe9321dfb2b7959f827c994583338afd3fae2b034c787b963c2c179e`.
- Intel DMG SHA-256: `dd2b0222eeabc11ea1a06a740aa4e22f2300787c965e6484194e09ac74512125`.
- Generic DMG SHA-256: `7f15b56de1b08996de56a9e6790afeda4bcc8b8e8cfb8790c6c3f7d666fc736f`.
- Apple Silicon ZIP SHA-256: `a0c59a08a127edb18a36c7119c2d6f7dd423d345454c3b79751cf3ae24fd8cdf`.
- Physical Intel hardware remains untested; verify on an Intel Mac when available.

## v1.5.3 release — 2026-09-23

- Source version: 1.5.3, build 270827, deployment target macOS 14.0.
- The published 1.5.3 download links select separate Apple Silicon and Intel
  DMGs; a notarized Apple Silicon ZIP and generic DMG are also available.
- Built a signed arm64 `build/GZWhisper.app`. Apple accepted app submission
  `e9f36619-47a3-4686-beef-71093726ef42` and DMG submission
  `c08e4ebf-4f62-45da-a42b-44fe15ef89fc`. Both tickets were stapled and
  validated. Gatekeeper accepts the app, DMG, extracted ZIP app, and mounted DMG
  app as `Notarized Developer ID`; strict code-signature checks passed.
- The notarytool profile `GZWhisper` is present and usable. The earlier
  unavailable-profile error was transient.
- ZIP was rebuilt after stapling. ZIP SHA-256:
  `3246dabaeb493f06117bd747f299afe43b74d411341c34fd72fce91897d89829`.
- DMG SHA-256: `fc1398b306556f9446f77f7f444e189085bf5595e81c7b537099177bf15c4fab`.
- Release packaging checks stable bundle ID `com.gzakharov.gzwhisper`, Team ID
  `BN3D9H4C7J`, Developer ID signing and the designated requirement against the
  previously installed 1.5.2 app. The requirements matched. After installing
  1.5.3 in `/Applications`, system + microphone recording started without a new
  macOS permission prompt. The test recording was removed through the app, and
  the existing 210 history entries remained available.
- Separate architecture builds were also completed. Apple Silicon app/DMG
  submissions `30eaafa1-cd19-4b80-a0f3-c809f352d76f` /
  `d875feab-fa7f-4dba-b0ea-bfe7fd751f88` were Accepted. Intel app/DMG
  submissions `565b966a-b976-420a-b435-b9cfae0ed293` /
  `c85ed5fa-e0eb-4bc5-a6d5-96fd76e70215` were Accepted. All four tickets
  were stapled. Each mounted DMG app passed strict signature, stapler, and
  Gatekeeper checks; its executable and Python runtime had the intended single
  architecture. Both wheelhouses passed clean offline installation/imports.
- Apple Silicon architecture-specific DMG SHA-256:
  `93e69404a862c5052f3d053f5e4d84b847ca50fffb0d6cbdc0c5ce4e90e14f2a`.
- Intel architecture-specific DMG SHA-256:
  `9944bc9fb13aab3c6a0cfbaf5f91a1102fb1340200cc31472e2be0c687599cab`.
- The main window was inspected after installing 1.5.3. Swift typechecking and
  isolated history behavior tests passed. Physical Intel hardware validation
  remains recommended.
- `build/` is generated and ignored by Git. The four archives above are the
  v1.5.3 GitHub release assets; the local 1.5.2 backup is not uploaded.

## Verified local release — 2026-09-09

- Version: 1.5.2, build 270826, Apple Silicon, macOS 12+.
- App submission: `e994ad23-63cf-432a-a004-700a90a5c6b5` — Accepted, no issues.
- DMG submission: `8314e95f-b1d0-4ba4-9278-c8203cb05cfc` — Accepted.
- Both tickets stapled and validated; both Gatekeeper assessments accepted with
  `source=Notarized Developer ID`. App verified again inside mounted DMG.
- Eight native wheel archives passed RECORD hash validation; clean offline install
  and imports of faster_whisper, huggingface_hub, onnxruntime and sympy passed.
- DMG SHA-256: `2711e1874ca35c24c36c5d97acc21e723a4642058e42a15e84e6039c62fc97f7`.
- Artifact: `build/GZWhisper-Installer-1.5.2.dmg`. Not uploaded to GitHub releases.

## Verified dual-architecture release — 2026-09-11

- Version: 1.5.2, build 270826, deployment target macOS 14.0 (covers macOS 14 and 15).
- Apple Silicon app submission: `e045493a-3f5a-4270-bbc4-0b1f6111c2c1` — Accepted.
- Apple Silicon DMG submission: `0eb75fb3-c7ca-4901-a3a8-ea772f0a1889` — Accepted.
- Intel app submission: `022f576c-037a-4aba-933f-a5f8ad8e2a4e` — Accepted.
- Intel DMG submission: `fb1dd7b1-b61e-4c32-97b5-57c4521ebf33` — Accepted.
- Both wheelhouses passed clean offline installation and imports. The Intel app
  executable and embedded Python ran as x86_64 through Rosetta without an early
  startup failure. A physical Intel Mac remains the recommended final hardware test.
- Mounted copies from both DMGs passed strict signature and Gatekeeper checks with
  `source=Notarized Developer ID`; both tickets were stapled and validated.
- Apple Silicon DMG SHA-256: `6b69f6f49e80250e5b1a1d2c69210e92e30a738d4dd0a96c1b060f1ed1ccd9db`.
- Intel DMG SHA-256: `bc876e4a14bd62f3fc842c441d6127103603e7fc370d2fc3c1b7503a73575ac0`.
- Artifacts: `build/releases/Apple-Silicon/GZWhisper-Installer-1.5.2-Apple-Silicon.dmg`
  and `build/releases/Intel/GZWhisper-Installer-1.5.2-Intel.dmg`. Not uploaded.
