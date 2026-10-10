#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/build/GZ Whisper Legacy.app}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.gzakharov.gzwhisper}"
EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-BN3D9H4C7J}"
# Prefer the renamed installed app, while still checking identity on first upgrade.
DEFAULT_REFERENCE_APP="/Applications/GZ Whisper Legacy.app"
if [[ ! -d "$DEFAULT_REFERENCE_APP" ]]; then
  DEFAULT_REFERENCE_APP="/Applications/GZWhisper.app"
fi
REFERENCE_APP="${REFERENCE_APP-$DEFAULT_REFERENCE_APP}"

[[ -d "$APP_PATH" ]] || { echo "App not found: $APP_PATH" >&2; exit 1; }

bundle_id="$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")"
signature="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
authority="$(printf '%s\n' "$signature" | sed -n 's/^Authority=//p' | head -n 1)"
team_id="$(printf '%s\n' "$signature" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"

[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || {
  echo "Bundle ID changed: $bundle_id (expected $EXPECTED_BUNDLE_ID)" >&2
  exit 1
}
[[ "$authority" == Developer\ ID\ Application:* ]] || {
  echo "Developer ID Application signature required; found: $authority" >&2
  exit 1
}
[[ "$team_id" == "$EXPECTED_TEAM_ID" ]] || {
  echo "Signing team changed: $team_id (expected $EXPECTED_TEAM_ID)" >&2
  exit 1
}

codesign --verify --deep --strict "$APP_PATH"

if [[ -n "$REFERENCE_APP" && -d "$REFERENCE_APP" ]]; then
  reference_bundle_id="$(plutil -extract CFBundleIdentifier raw "$REFERENCE_APP/Contents/Info.plist")"
  if [[ "$reference_bundle_id" == "$EXPECTED_BUNDLE_ID" ]]; then
    reference_requirement="$(codesign -dr - "$REFERENCE_APP" 2>&1 | sed -n 's/^designated => //p')"
    current_requirement="$(codesign -dr - "$APP_PATH" 2>&1 | sed -n 's/^designated => //p')"
    [[ -n "$reference_requirement" && "$reference_requirement" == "$current_requirement" ]] || {
      echo "Designated requirement differs from installed $REFERENCE_APP." >&2
      echo "macOS may ask for recording permission again after this update." >&2
      exit 1
    }
  fi
fi

echo "Release identity verified: $bundle_id / $team_id"
