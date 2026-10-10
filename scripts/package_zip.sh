#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-GZ Whisper Legacy}"
ZIP_BASENAME="${ZIP_BASENAME:-GZWhisper-Legacy-macOS-1.5.5}"
APP_DIR="$BUILD_DIR/${APP_BUNDLE_NAME}.app"
ZIP_PATH="$BUILD_DIR/${ZIP_BASENAME}.zip"
ZIP_STAGING_DIR="$BUILD_DIR/${ZIP_BASENAME}-staging"
INSTRUCTIONS_PATH="$ZIP_STAGING_DIR/Install_Instructions.txt"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App not found: $APP_DIR"
  echo "Run ./scripts/build_app.sh first."
  exit 1
fi

bash "$ROOT_DIR/scripts/check_release_identity.sh" "$APP_DIR"

rm -rf "$ZIP_STAGING_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$ZIP_STAGING_DIR"

DITTONORSRC=1 ditto --norsrc "$APP_DIR" "$ZIP_STAGING_DIR/${APP_BUNDLE_NAME}.app"
cat > "$INSTRUCTIONS_PATH" <<TEXT
Install GZ Whisper Legacy from ZIP:

1. Extract this ZIP archive.
2. Move ${APP_BUNDLE_NAME}.app to /Applications.
3. Open ${APP_BUNDLE_NAME}.app from /Applications.

When updating GZWhisper, quit the old app and keep only the updated Legacy app
in Applications. Your existing history, models, and settings are retained.
GZ Whisper Legacy receives fixes for user-reported bugs; new features are frozen.
The new GZ Whisper for iOS and macOS is a separate application.

If macOS blocks launch:
1. In Applications, right-click ${APP_BUNDLE_NAME}.app and choose Open.
2. If needed, open System Settings -> Privacy & Security.
3. Scroll down and click Open Anyway for GZ Whisper Legacy.
4. Confirm with your Mac password or Touch ID.

TEXT

(
  cd "$ZIP_STAGING_DIR"
  COPYFILE_DISABLE=1 DITTONORSRC=1 ditto -c -k --norsrc . "$ZIP_PATH"
)

rm -rf "$ZIP_STAGING_DIR"

echo "Created: $ZIP_PATH"
