#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${PYTHON_BIN:-}" ]]; then
  PYTHON_BIN="$PYTHON_BIN"
elif command -v /usr/local/bin/python3.12 >/dev/null 2>&1; then
  PYTHON_BIN="/usr/local/bin/python3.12"
elif command -v /opt/homebrew/bin/python3.12 >/dev/null 2>&1; then
  PYTHON_BIN="/opt/homebrew/bin/python3.12"
elif command -v python3.12 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3.12)"
else
  PYTHON_BIN="python3"
fi
INCLUDE_WHEELHOUSE="${INCLUDE_WHEELHOUSE:-1}"
FRAMEWORK_DEST="$ROOT_DIR/Resources/Python.framework"
RUNTIME_DEST="$ROOT_DIR/Resources/python"
WHEELHOUSE_DEST="$ROOT_DIR/Resources/wheelhouse"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python executable not found: $PYTHON_BIN"
  exit 1
fi

PYTHON_FRAMEWORK_SOURCE="$($PYTHON_BIN - <<'PY'
import pathlib
import sysconfig

framework = sysconfig.get_config_var("PYTHONFRAMEWORK")
prefix = sysconfig.get_config_var("PYTHONFRAMEWORKPREFIX")

if not framework or not prefix:
    raise SystemExit(1)

print(pathlib.Path(prefix) / f"{framework}.framework")
PY
)" || true

PYTHON_MINOR="$("$PYTHON_BIN" -c 'import sys; print(sys.version_info.minor)')"
PYTHON_VERSION="$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")')"
if [[ "$PYTHON_MINOR" -lt 10 || "$PYTHON_MINOR" -gt 12 ]]; then
  echo "Unsupported Python version for embedded runtime: $PYTHON_VERSION"
  echo "Use Python 3.10-3.12 (recommended: 3.12)."
  exit 1
fi

if ! file "$PYTHON_BIN" | grep -q "arm64"; then
  echo "Selected Python runtime is not arm64: $PYTHON_BIN"
  echo "Use an Apple Silicon interpreter, for example:"
  echo "PYTHON_BIN=Resources/python/bin/python3 ./scripts/prepare_embedded_python.sh"
  exit 1
fi

EMBEDDED_RUNTIME_DESC=""
if [[ -n "$PYTHON_FRAMEWORK_SOURCE" && -d "$PYTHON_FRAMEWORK_SOURCE" && -x "$PYTHON_FRAMEWORK_SOURCE/Versions/Current/bin/python3" ]]; then
  rm -rf "$FRAMEWORK_DEST"
  cp -R "$PYTHON_FRAMEWORK_SOURCE" "$FRAMEWORK_DEST"
  EMBEDDED_RUNTIME_DESC="$FRAMEWORK_DEST"
else
  PYTHON_PREFIX="$("$PYTHON_BIN" -c 'import sys; print(sys.prefix)')"
  if [[ ! -d "$PYTHON_PREFIX" || ! -x "$PYTHON_PREFIX/bin/python3" ]]; then
    echo "Could not resolve a copyable standalone Python runtime from $PYTHON_BIN"
    exit 1
  fi
  rm -rf "$RUNTIME_DEST"
  cp -R "$PYTHON_PREFIX" "$RUNTIME_DEST"
  EMBEDDED_RUNTIME_DESC="$RUNTIME_DEST"
fi

if [[ "$INCLUDE_WHEELHOUSE" == "1" ]]; then
  rm -rf "$WHEELHOUSE_DEST"
  mkdir -p "$WHEELHOUSE_DEST"

  # Download ASR runtime wheels.
  "$PYTHON_BIN" -m pip download \
    --only-binary=:all: \
    --dest "$WHEELHOUSE_DEST" \
    faster-whisper \
    huggingface_hub
fi

echo "Embedded runtime prepared: $EMBEDDED_RUNTIME_DESC"
if [[ "$INCLUDE_WHEELHOUSE" == "1" ]]; then
  echo "Wheelhouse prepared: $WHEELHOUSE_DEST"
fi
