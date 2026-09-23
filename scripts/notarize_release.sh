#!/usr/bin/env bash
# Run after build_app.sh. Credentials must already be stored in Keychain.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
APP_PATH="$BUILD_DIR/${APP_BUNDLE_NAME:-GZWhisper}.app"
bash "$ROOT_DIR/scripts/check_release_identity.sh" "$APP_PATH"
export NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-GZWhisper}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-20m}"
AUTHORITY="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
[[ "$AUTHORITY" == Developer\ ID\ Application:* ]] || { echo 'Developer ID Application signature required.' >&2; exit 1; }
codesign --verify --deep --strict "$APP_PATH"
xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" >/dev/null
ARCHIVE="$BUILD_DIR/GZWhisper-notarization.zip"
ditto -c -k --keepParent "$APP_PATH" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARYTOOL_PROFILE" --wait --timeout "$NOTARY_TIMEOUT"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"
"$ROOT_DIR/scripts/build_dmg.sh"
