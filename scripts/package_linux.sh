#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PACKAGE_DIR="$BUILD_DIR/GZWhisper-linux"
ARCHIVE_PATH="$BUILD_DIR/GZWhisper-linux.tar.gz"

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/linux" "$PACKAGE_DIR/scripts" "$PACKAGE_DIR/Resources"

cp "$ROOT_DIR/linux/gzwhisper_linux.py" "$PACKAGE_DIR/linux/gzwhisper_linux.py"
cp "$ROOT_DIR/Resources/transcription_worker.py" "$PACKAGE_DIR/Resources/transcription_worker.py"
cp "$ROOT_DIR/scripts/install_linux.sh" "$PACKAGE_DIR/scripts/install_linux.sh"
cp "$ROOT_DIR/scripts/uninstall_linux.sh" "$PACKAGE_DIR/scripts/uninstall_linux.sh"

if [[ -f "$ROOT_DIR/Resources/AppIcon.png" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.png" "$PACKAGE_DIR/Resources/AppIcon.png"
fi

chmod +x "$PACKAGE_DIR/linux/gzwhisper_linux.py" "$PACKAGE_DIR/scripts/install_linux.sh" "$PACKAGE_DIR/scripts/uninstall_linux.sh"

cat > "$PACKAGE_DIR/README-Linux.txt" <<'TXT'
GZWhisper Linux package

Install:
  ./scripts/install_linux.sh

Run:
  ~/.local/bin/gzwhisper-linux

Uninstall:
  ./scripts/uninstall_linux.sh
TXT

rm -f "$ARCHIVE_PATH"
tar -C "$BUILD_DIR" -czf "$ARCHIVE_PATH" "GZWhisper-linux"

echo "Created: $ARCHIVE_PATH"
