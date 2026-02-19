#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
APP_ID="gzwhisper-linux"
LIB_DIR="$PREFIX/lib/$APP_ID"
BIN_PATH="$PREFIX/bin/gzwhisper-linux"
DESKTOP_PATH="$HOME/.local/share/applications/$APP_ID.desktop"
ICON_PATH="$HOME/.local/share/icons/hicolor/256x256/apps/$APP_ID.png"
RUNTIME_DATA_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/$APP_ID"

rm -rf "$LIB_DIR"
rm -f "$BIN_PATH"
rm -f "$DESKTOP_PATH"
rm -f "$ICON_PATH"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

cat <<EOF
Removed launcher and installed files.

Runtime data was kept at:
  $RUNTIME_DATA_PATH

To remove it too:
  rm -rf "$RUNTIME_DATA_PATH"
EOF
