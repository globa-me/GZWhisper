#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-GZWhisper-1.3}"
ZIP_BASENAME="${ZIP_BASENAME:-GZWhisper-macOS-1.3}"
APP_DIR="$BUILD_DIR/${APP_BUNDLE_NAME}.app"
ZIP_PATH="$BUILD_DIR/${ZIP_BASENAME}.zip"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App not found: $APP_DIR"
  echo "Run ./scripts/build_app.sh first."
  exit 1
fi

rm -f "$ZIP_PATH"
(
  cd "$BUILD_DIR"
  ditto -c -k --keepParent "${APP_BUNDLE_NAME}.app" "${ZIP_BASENAME}.zip"
)

echo "Created: $ZIP_PATH"
