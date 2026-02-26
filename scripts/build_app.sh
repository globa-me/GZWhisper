#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="GZWhisper"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-12.0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
APP_BIN="$BUILD_DIR/${APP_NAME}-arm64"
PYTHON_FRAMEWORK_SOURCE="${PYTHON_FRAMEWORK_SOURCE:-$ROOT_DIR/Resources/Python.framework}"
PYTHON_RUNTIME_SOURCE="${PYTHON_RUNTIME_SOURCE:-$ROOT_DIR/Resources/python}"
WHEELHOUSE_SOURCE="${WHEELHOUSE_SOURCE:-$ROOT_DIR/Resources/wheelhouse}"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
mkdir -p "$MODULE_CACHE_DIR"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

swiftc \
  -parse-as-library \
  -module-name "$APP_NAME" \
  -target "arm64-apple-macos${MIN_MACOS_VERSION}" \
  -sdk "$SDK_PATH" \
  -o "$APP_BIN" \
  "$ROOT_DIR"/Sources/*.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework UniformTypeIdentifiers

mv "$APP_BIN" "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/Resources/transcription_worker.py" "$RESOURCES_DIR/transcription_worker.py"
chmod +x "$RESOURCES_DIR/transcription_worker.py"

if [[ -f "$ROOT_DIR/Resources/AppIcon.png" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.png" "$RESOURCES_DIR/AppIcon.png"
fi
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -d "$PYTHON_FRAMEWORK_SOURCE" ]]; then
  rm -rf "$FRAMEWORKS_DIR/Python.framework"
  cp -R "$PYTHON_FRAMEWORK_SOURCE" "$FRAMEWORKS_DIR/Python.framework"
fi

if [[ -d "$PYTHON_RUNTIME_SOURCE" ]]; then
  rm -rf "$RESOURCES_DIR/python"
  cp -R "$PYTHON_RUNTIME_SOURCE" "$RESOURCES_DIR/python"
fi

if [[ -d "$WHEELHOUSE_SOURCE" ]]; then
  rm -rf "$RESOURCES_DIR/wheelhouse"
  cp -R "$WHEELHOUSE_SOURCE" "$RESOURCES_DIR/wheelhouse"
fi

EMBEDDED_PYTHON=""
if [[ -x "$RESOURCES_DIR/python/bin/python3" ]]; then
  EMBEDDED_PYTHON="$RESOURCES_DIR/python/bin/python3"
elif [[ -x "$FRAMEWORKS_DIR/Python.framework/Versions/Current/bin/python3" ]]; then
  EMBEDDED_PYTHON="$FRAMEWORKS_DIR/Python.framework/Versions/Current/bin/python3"
fi

if [[ -z "$EMBEDDED_PYTHON" ]]; then
  echo "Embedded Python runtime not found."
  echo "Add runtime files to Resources/Python.framework or Resources/python before building."
  echo "Use ./scripts/prepare_embedded_python.sh to prepare runtime assets."
  exit 1
fi

if ! file "$EMBEDDED_PYTHON" | grep -q "arm64"; then
  echo "Embedded Python runtime is not arm64: $EMBEDDED_PYTHON"
  echo "Prepare an Apple Silicon Python runtime before building."
  exit 1
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ru</string>
    <key>CFBundleDisplayName</key>
    <string>GZWhisper</string>
    <key>CFBundleExecutable</key>
    <string>GZWhisper</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.gzakharov.gzwhisper</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>GZWhisper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/$APP_NAME"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi

echo "Built app: $APP_DIR"
