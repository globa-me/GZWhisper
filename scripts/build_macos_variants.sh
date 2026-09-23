#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_ROOT="${RELEASE_ROOT:-$ROOT_DIR/build/releases}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
APP_VERSION="${APP_VERSION:-1.5.4}"
APP_BUILD="${APP_BUILD:-270828}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-auto}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-GZWhisper}"
INTEL_RUNTIME_ROOT="$RELEASE_ROOT/runtime-x86_64"
INTEL_PYTHON="$INTEL_RUNTIME_ROOT/python/bin/python3"
INTEL_WHEELHOUSE="$INTEL_RUNTIME_ROOT/wheelhouse"
INTEL_PYTHON_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20250612/cpython-3.12.11%2B20250612-x86_64-apple-darwin-install_only_stripped.tar.gz"
INTEL_PYTHON_SHA256="16797cdee1b879ce0f32d9162f2a3af8b91d8ccb663c75ed3afc2384845c24d7"
NOTARIZE="${NOTARIZE:-1}"

mkdir -p "$RELEASE_ROOT"

if [[ ! -x "$INTEL_PYTHON" ]]; then
  archive="$RELEASE_ROOT/cpython-3.12.11-x86_64.tar.gz"
  if [[ ! -f "$archive" ]]; then
    curl -fL --retry 3 -o "$archive" "$INTEL_PYTHON_URL"
  fi
  actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual_sha" != "$INTEL_PYTHON_SHA256" ]]; then
    echo "Intel Python archive checksum mismatch: $actual_sha" >&2
    exit 1
  fi
  rm -rf "$INTEL_RUNTIME_ROOT/python"
  mkdir -p "$INTEL_RUNTIME_ROOT"
  tar -xzf "$archive" -C "$INTEL_RUNTIME_ROOT"
fi

if ! lipo -archs "$INTEL_PYTHON" | tr ' ' '\n' | grep -qx x86_64; then
  echo "Intel Python runtime is not x86_64: $INTEL_PYTHON" >&2
  exit 1
fi

if [[ ! -d "$INTEL_WHEELHOUSE" ]]; then
  mkdir -p "$INTEL_WHEELHOUSE"
  "$INTEL_PYTHON" -m pip download \
    --only-binary=:all: \
    --platform macosx_12_0_x86_64 \
    --python-version 312 \
    --implementation cp \
    --abi cp312 \
    --dest "$INTEL_WHEELHOUSE" \
    --requirement "$ROOT_DIR/Resources/requirements-macos.txt"
fi

TARGET_ARCH=x86_64 TARGET_PLATFORM=macosx_12_0_x86_64 \
  "$ROOT_DIR/scripts/check_wheelhouse.sh" \
  "$INTEL_PYTHON" "$INTEL_WHEELHOUSE" "$ROOT_DIR/Resources/requirements-macos.txt"

build_variant() {
  local architecture="$1"
  local label="$2"
  local variant_dir="$RELEASE_ROOT/$label"
  local runtime_source="$3"
  local wheelhouse_source="$4"

  mkdir -p "$variant_dir"
  BUILD_DIR="$variant_dir" \
  TARGET_ARCH="$architecture" \
  TARGET_PLATFORM="macosx_12_0_${architecture}" \
  MIN_MACOS_VERSION="$MIN_MACOS_VERSION" \
  APP_VERSION="$APP_VERSION" \
  APP_BUILD="$APP_BUILD" \
  SIGNING_IDENTITY="$SIGNING_IDENTITY" \
  ALLOW_APPLE_DEVELOPMENT_FALLBACK=0 \
  PYTHON_FRAMEWORK_SOURCE="$variant_dir/no-python-framework" \
  PYTHON_RUNTIME_SOURCE="$runtime_source" \
  WHEELHOUSE_SOURCE="$wheelhouse_source" \
    "$ROOT_DIR/scripts/build_app.sh"

  if [[ "$NOTARIZE" == "1" ]]; then
    BUILD_DIR="$variant_dir" \
    APP_TITLE="GZWhisper $APP_VERSION ($label)" \
    DMG_NAME="GZWhisper-Installer-$APP_VERSION-$label" \
    VOL_NAME="GZWhisper $APP_VERSION $label" \
    NOTARYTOOL_PROFILE="$NOTARYTOOL_PROFILE" \
    SIGNING_IDENTITY="$SIGNING_IDENTITY" \
      "$ROOT_DIR/scripts/notarize_release.sh"
  else
    BUILD_DIR="$variant_dir" \
    APP_TITLE="GZWhisper $APP_VERSION ($label)" \
    DMG_NAME="GZWhisper-Installer-$APP_VERSION-$label" \
    VOL_NAME="GZWhisper $APP_VERSION $label" \
      "$ROOT_DIR/scripts/build_dmg.sh"
  fi
}

build_variant arm64 Apple-Silicon "$ROOT_DIR/Resources/python" "$ROOT_DIR/Resources/wheelhouse"
build_variant x86_64 Intel "$INTEL_RUNTIME_ROOT/python" "$INTEL_WHEELHOUSE"

echo "Built macOS release variants in: $RELEASE_ROOT"
