#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This installer is for Linux only."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
APP_ID="gzwhisper-linux"
APP_NAME="GZWhisper Linux"
LIB_DIR="$PREFIX/lib/$APP_ID"
BIN_DIR="$PREFIX/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

mkdir -p "$LIB_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

install -m 755 "$ROOT_DIR/linux/gzwhisper_linux.py" "$LIB_DIR/gzwhisper_linux.py"
install -m 644 "$ROOT_DIR/Resources/transcription_worker.py" "$LIB_DIR/transcription_worker.py"

if [[ -f "$ROOT_DIR/Resources/AppIcon.png" ]]; then
  install -m 644 "$ROOT_DIR/Resources/AppIcon.png" "$ICON_DIR/$APP_ID.png"
fi

cat > "$BIN_DIR/gzwhisper-linux" <<EOF
#!/usr/bin/env bash
exec python3 "$LIB_DIR/gzwhisper_linux.py" "\$@"
EOF
chmod +x "$BIN_DIR/gzwhisper-linux"

cat > "$DESKTOP_DIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=Local audio and video transcription
Exec=$BIN_DIR/gzwhisper-linux
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Utility;
Keywords=whisper;transcription;audio;video;
StartupNotify=true
EOF

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

cat <<EOF
Installed $APP_NAME.

Run from terminal:
  $BIN_DIR/gzwhisper-linux

or find it in your application menu.

If '$BIN_DIR' is not in PATH, add this line to your shell profile:
  export PATH="\$HOME/.local/bin:\$PATH"
EOF
