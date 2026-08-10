#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-GZWhisper}"
ZIP_BASENAME="${ZIP_BASENAME:-GZWhisper-macOS-1.4.3}"
APP_DIR="$BUILD_DIR/${APP_BUNDLE_NAME}.app"
ZIP_PATH="$BUILD_DIR/${ZIP_BASENAME}.zip"
ZIP_STAGING_DIR="$BUILD_DIR/${ZIP_BASENAME}-staging"
BYPASS_SCRIPT_NAME="Enable_GZWhisper.command"
BYPASS_SCRIPT_SRC="$ROOT_DIR/Resources/$BYPASS_SCRIPT_NAME"
BYPASS_SCRIPT_DST="$ZIP_STAGING_DIR/$BYPASS_SCRIPT_NAME"
INSTRUCTIONS_PATH="$ZIP_STAGING_DIR/Install_Instructions.txt"
TERMINAL_FIX_PATH="$ZIP_STAGING_DIR/Run_If_Blocked.txt"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App not found: $APP_DIR"
  echo "Run ./scripts/build_app.sh first."
  exit 1
fi

if [[ ! -f "$BYPASS_SCRIPT_SRC" ]]; then
  echo "Bypass script not found: $BYPASS_SCRIPT_SRC"
  exit 1
fi

rm -rf "$ZIP_STAGING_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$ZIP_STAGING_DIR"

DITTONORSRC=1 ditto --norsrc "$APP_DIR" "$ZIP_STAGING_DIR/${APP_BUNDLE_NAME}.app"
ditto --noextattr --noqtn "$BYPASS_SCRIPT_SRC" "$BYPASS_SCRIPT_DST"
chmod +x "$BYPASS_SCRIPT_DST"
xattr -c "$BYPASS_SCRIPT_DST" 2>/dev/null || true

cat > "$INSTRUCTIONS_PATH" <<'TEXT'
Install GZWhisper from ZIP:

1. Extract this ZIP archive.
2. Move GZWhisper.app to /Applications.
3. Open GZWhisper.app from /Applications.

If macOS blocks launch:
1. In Applications, right-click GZWhisper.app and choose Open.
2. If needed, open System Settings -> Privacy & Security.
3. Scroll down and click Open Anyway for GZWhisper.
4. Confirm with your Mac password or Touch ID.

Optional helper:
Run Enable_GZWhisper.command only after GZWhisper.app has been copied to /Applications.
TEXT

cat > "$TERMINAL_FIX_PATH" <<'TEXT'
If GZWhisper is blocked:

Preferred fix:
1) Open System Settings -> Privacy & Security.
2) Scroll down and click Open Anyway for GZWhisper.
3) Confirm with your Mac password or Touch ID.
4) Open GZWhisper again from /Applications.

If you need Terminal:

sudo xattr -dr com.apple.quarantine "/Applications/GZWhisper.app"
open "/Applications/GZWhisper.app"
TEXT

(
  cd "$ZIP_STAGING_DIR"
  COPYFILE_DISABLE=1 DITTONORSRC=1 ditto -c -k --norsrc . "$ZIP_PATH"
)

rm -rf "$ZIP_STAGING_DIR"

echo "Created: $ZIP_PATH"
