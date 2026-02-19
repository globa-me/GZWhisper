#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/GZWhisper.app"
ZIP_PATH="$BUILD_DIR/GZWhisper-macOS.zip"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App not found: $APP_DIR"
  echo "Run ./scripts/build_app.sh first."
  exit 1
fi

rm -f "$ZIP_PATH"
(
  cd "$BUILD_DIR"
  ditto -c -k --keepParent "GZWhisper.app" "GZWhisper-macOS.zip"
)

echo "Created: $ZIP_PATH"
