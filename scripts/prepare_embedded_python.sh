#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
INCLUDE_WHEELHOUSE="${INCLUDE_WHEELHOUSE:-1}"
FRAMEWORK_DEST="$ROOT_DIR/Resources/Python.framework"
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
)"

if [[ -z "$PYTHON_FRAMEWORK_SOURCE" || ! -d "$PYTHON_FRAMEWORK_SOURCE" ]]; then
  echo "Could not locate Python.framework for $PYTHON_BIN"
  exit 1
fi

PYTHON_EXECUTABLE="$PYTHON_FRAMEWORK_SOURCE/Versions/Current/bin/python3"
if [[ ! -x "$PYTHON_EXECUTABLE" ]]; then
  echo "Python executable not found inside framework: $PYTHON_EXECUTABLE"
  exit 1
fi

if ! file "$PYTHON_EXECUTABLE" | grep -q "arm64"; then
  echo "Selected Python runtime is not arm64: $PYTHON_EXECUTABLE"
  echo "Use an Apple Silicon interpreter, for example:"
  echo "PYTHON_BIN=/opt/homebrew/bin/python3 ./scripts/prepare_embedded_python.sh"
  exit 1
fi

rm -rf "$FRAMEWORK_DEST"
cp -R "$PYTHON_FRAMEWORK_SOURCE" "$FRAMEWORK_DEST"

if [[ "$INCLUDE_WHEELHOUSE" == "1" ]]; then
  rm -rf "$WHEELHOUSE_DEST"
  mkdir -p "$WHEELHOUSE_DEST"

  "$PYTHON_BIN" -m pip download \
    --only-binary=:all: \
    --dest "$WHEELHOUSE_DEST" \
    faster-whisper huggingface_hub
fi

echo "Embedded runtime prepared: $FRAMEWORK_DEST"
if [[ "$INCLUDE_WHEELHOUSE" == "1" ]]; then
  echo "Wheelhouse prepared: $WHEELHOUSE_DEST"
fi
