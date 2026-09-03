#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_MODULE_NAME="GZWhisper"
APP_EXECUTABLE_NAME="${APP_EXECUTABLE_NAME:-GZWhisper}"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-GZWhisper}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-GZWhisper}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.gzakharov.gzwhisper}"
APP_DIR="$BUILD_DIR/$APP_BUNDLE_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-12.0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-auto}"
ALLOW_APPLE_DEVELOPMENT_FALLBACK="${ALLOW_APPLE_DEVELOPMENT_FALLBACK:-1}"
APP_VERSION="${APP_VERSION:-1.5.2}"
APP_BUILD="${APP_BUILD:-270826}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
APP_BIN="$BUILD_DIR/${APP_MODULE_NAME}-arm64"
PYTHON_FRAMEWORK_SOURCE="${PYTHON_FRAMEWORK_SOURCE:-$ROOT_DIR/Resources/Python.framework}"
PYTHON_RUNTIME_SOURCE="${PYTHON_RUNTIME_SOURCE:-$ROOT_DIR/Resources/python}"
WHEELHOUSE_SOURCE="${WHEELHOUSE_SOURCE:-$ROOT_DIR/Resources/wheelhouse}"
ENTITLEMENTS_FILE="${ENTITLEMENTS_FILE:-$ROOT_DIR/Resources/GZWhisper.entitlements}"

detect_signing_identity() {
  local identities
  local certificate_dir
  local certificate_file
  local candidate_hash
  local certificate_hash
  local preferred_kind

  if ! identities="$(security find-identity -v -p codesigning 2>/dev/null)"; then
    return 1
  fi

  certificate_dir="$(mktemp -d)"
  if ! security find-certificate -a -p 2>/dev/null | awk -v dir="$certificate_dir" '
      /BEGIN CERTIFICATE/ {
        count += 1
        file = sprintf("%s/cert-%04d.pem", dir, count)
      }
      file != "" { print > file }
      /END CERTIFICATE/ {
        close(file)
        file = ""
      }
    '; then
    rm -rf "$certificate_dir"
    return 1
  fi

  for preferred_kind in "Developer ID Application" "Apple Development"; do
    if [[ "$preferred_kind" == "Apple Development" && "$ALLOW_APPLE_DEVELOPMENT_FALLBACK" != "1" ]]; then
      continue
    fi

    while IFS= read -r candidate_hash; do
      [[ -n "$candidate_hash" ]] || continue

      for certificate_file in "$certificate_dir"/*.pem; do
        [[ -f "$certificate_file" ]] || continue
        certificate_hash="$(
          openssl x509 -in "$certificate_file" -noout -fingerprint -sha1 2>/dev/null \
            | sed 's/.*=//; s/://g'
        )"
        [[ "$certificate_hash" == "$candidate_hash" ]] || continue

        if security verify-cert \
          -c "$certificate_file" \
          -p codeSign \
          -R ocsp \
          -q >/dev/null 2>&1; then
          rm -rf "$certificate_dir"
          echo "$candidate_hash"
          return 0
        fi

        echo "Warning: skipping revoked or otherwise unusable signing identity: $candidate_hash" >&2
        break
      done
    done < <(
      echo "$identities" \
        | sed -n "s/^[[:space:]]*[0-9]*) \([0-9A-Fa-f][0-9A-Fa-f]*\) \"$preferred_kind:.*\"/\1/p"
    )
  done

  rm -rf "$certificate_dir"
  return 1
}

if [[ "$SIGNING_IDENTITY" == "auto" ]]; then
  if AUTO_SIGNING_IDENTITY="$(detect_signing_identity)"; then
    if [[ -n "$AUTO_SIGNING_IDENTITY" ]]; then
      SIGNING_IDENTITY="$AUTO_SIGNING_IDENTITY"
    else
      SIGNING_IDENTITY="-"
    fi
  else
    echo "Warning: no usable signing identity was selected."
    echo "Falling back to ad-hoc signing. macOS may ask for privacy permissions again after each update."
    SIGNING_IDENTITY="-"
  fi
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
mkdir -p "$MODULE_CACHE_DIR"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

swiftc \
  -parse-as-library \
  -module-name "$APP_MODULE_NAME" \
  -target "arm64-apple-macos${MIN_MACOS_VERSION}" \
  -sdk "$SDK_PATH" \
  -o "$APP_BIN" \
  "$ROOT_DIR"/Sources/*.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework ScreenCaptureKit \
  -framework CoreMedia \
  -framework UniformTypeIdentifiers

mv "$APP_BIN" "$MACOS_DIR/$APP_EXECUTABLE_NAME"

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

EMBEDDED_PY_VERSION="$(PYTHONDONTWRITEBYTECODE=1 "$EMBEDDED_PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')"
EMBEDDED_PY_MINOR="$(PYTHONDONTWRITEBYTECODE=1 "$EMBEDDED_PYTHON" -c 'import sys; print(sys.version_info.minor)')"
if [[ "$EMBEDDED_PY_MINOR" -ne 12 ]]; then
  echo "Embedded Python runtime version is unsupported: $EMBEDDED_PY_VERSION"
  echo "Use Python 3.12 so the runtime matches the locked macOS wheelhouse."
  exit 1
fi

if [[ ! -d "$RESOURCES_DIR/wheelhouse" ]]; then
  echo "Bundled wheelhouse not found. Run scripts/prepare_embedded_python.sh first."
  exit 1
fi

"$ROOT_DIR/scripts/check_wheelhouse.sh" \
  "$EMBEDDED_PYTHON" \
  "$RESOURCES_DIR/wheelhouse" \
  "$ROOT_DIR/Resources/requirements-macos.txt"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ru</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${APP_BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>GZWhisper needs microphone access to record audio.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/$APP_EXECUTABLE_NAME"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Warning: building with ad-hoc signature."
  echo "Public distribution on other Macs will require manual approval after the app is copied to /Applications."
  echo "macOS privacy permissions like Screen Recording and System Audio may be treated as new on every update."
  codesign --force --deep --entitlements "$ENTITLEMENTS_FILE" --sign - "$APP_DIR" >/dev/null 2>&1 || true
else
  echo "Signing app with identity: $SIGNING_IDENTITY"
  if security find-identity -v -p codesigning 2>/dev/null \
    | grep -F "$SIGNING_IDENTITY" \
    | grep -q '"Apple Development:'; then
    echo "Warning: Apple Development signing is for local testing on your own Macs."
    echo "Public releases should use Developer ID Application and notarization."
  fi
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_FILE" --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
fi

echo "Built app: $APP_DIR"
