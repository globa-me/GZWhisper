#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${1:-$ROOT_DIR/Resources/python/bin/python3}"
WHEELHOUSE_DIR="${2:-$ROOT_DIR/Resources/wheelhouse}"
REQUIREMENTS_FILE="${3:-$ROOT_DIR/Resources/requirements-macos.txt}"
TARGET_ARCH="${TARGET_ARCH:-arm64}"
TARGET_PLATFORM="${TARGET_PLATFORM:-macosx_12_0_${TARGET_ARCH}}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Wheelhouse check Python is not executable: $PYTHON_BIN"
  exit 1
fi

if [[ ! -d "$WHEELHOUSE_DIR" ]]; then
  echo "Wheelhouse directory not found: $WHEELHOUSE_DIR"
  exit 1
fi

if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
  echo "Locked requirements not found: $REQUIREMENTS_FILE"
  exit 1
fi

CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gzwhisper-wheelhouse-check.XXXXXX")"

cleanup() {
  case "$CHECK_DIR" in
    "${TMPDIR:-/tmp}"/gzwhisper-wheelhouse-check.*)
      rm -rf "$CHECK_DIR"
      ;;
    *)
      echo "Refusing to remove unexpected temporary path: $CHECK_DIR" >&2
      ;;
  esac
}
trap cleanup EXIT

echo "Checking wheel resolution for Python 3.12 on $TARGET_PLATFORM..."
if ! lipo -archs "$PYTHON_BIN" | tr ' ' '\n' | grep -qx "$TARGET_ARCH"; then
  echo "Wheelhouse check Python does not contain $TARGET_ARCH: $PYTHON_BIN" >&2
  exit 1
fi
"$PYTHON_BIN" -m pip download \
  --no-index \
  --find-links "$WHEELHOUSE_DIR" \
  --only-binary=:all: \
  --platform "$TARGET_PLATFORM" \
  --python-version 312 \
  --implementation cp \
  --abi cp312 \
  --dest "$CHECK_DIR/resolved" \
  --requirement "$REQUIREMENTS_FILE"

echo "Testing a clean offline installation..."
"$PYTHON_BIN" -m venv "$CHECK_DIR/venv"
"$CHECK_DIR/venv/bin/python3" -m pip install \
  --no-index \
  --find-links "$WHEELHOUSE_DIR" \
  --requirement "$REQUIREMENTS_FILE"
"$CHECK_DIR/venv/bin/python3" -m pip check
"$CHECK_DIR/venv/bin/python3" -c "import faster_whisper, huggingface_hub, onnxruntime, sympy"

if ! lipo -archs "$CHECK_DIR/venv/bin/python3" | tr ' ' '\n' | grep -qx "$TARGET_ARCH"; then
  echo "Clean venv Python does not contain $TARGET_ARCH" >&2
  exit 1
fi

echo "Wheelhouse check passed."
