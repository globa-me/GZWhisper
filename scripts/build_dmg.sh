#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-GZWhisper}"
APP_TITLE="${APP_TITLE:-GZWhisper 1.5.1}"
APP_BUNDLE="$APP_BUNDLE_NAME.app"
APP_PATH="$BUILD_DIR/$APP_BUNDLE"
DMG_NAME="${DMG_NAME:-GZWhisper-Installer-1.5.1}"
DMG_PATH="$BUILD_DIR/${DMG_NAME}.dmg"
TEMP_DMG="$BUILD_DIR/${DMG_NAME}-temp.dmg"
VOL_NAME="${VOL_NAME:-GZWhisper 1.5.1 Installer}"
STAGING_DIR="$BUILD_DIR/dmg-staging"
BG_DIR="$STAGING_DIR/.background"
BG_PATH="$BG_DIR/background.png"
MOUNT_POINT="/Volumes/$VOL_NAME"
BYPASS_SCRIPT_NAME="Enable_GZWhisper.command"
BYPASS_SCRIPT_SRC="$ROOT_DIR/Resources/$BYPASS_SCRIPT_NAME"
BYPASS_SCRIPT_DST="$STAGING_DIR/$BYPASS_SCRIPT_NAME"
INSTRUCTIONS_PATH="$STAGING_DIR/Install_Instructions.txt"
TERMINAL_FIX_PATH="$STAGING_DIR/Run_If_Blocked.txt"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-20m}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  echo "Run ./scripts/build_app.sh first."
  exit 1
fi

if [[ ! -f "$BYPASS_SCRIPT_SRC" ]]; then
  echo "Bypass script not found: $BYPASS_SCRIPT_SRC"
  exit 1
fi

APP_AUTHORITY="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n 's/^Authority=//p' | head -n 1 || true)"
APP_ASSESSMENT="$(spctl -a -vv "$APP_PATH" 2>&1 || true)"

if [[ "$APP_AUTHORITY" == Developer\ ID\ Application:* ]]; then
  echo "App signing identity: $APP_AUTHORITY"
elif [[ "$APP_AUTHORITY" == Apple\ Development:* ]]; then
  echo "Warning: app is signed with Apple Development."
  echo "This is suitable for local testing only; public releases should use Developer ID Application + notarization."
else
  echo "Warning: app is not signed with Developer ID Application."
fi

if [[ "$APP_ASSESSMENT" != *": accepted"* ]]; then
  echo "Gatekeeper assessment on this Mac:"
  echo "$APP_ASSESSMENT"
  echo "Unsigned or development-signed builds are better distributed as ZIP archives."
  echo "Users should move the app to /Applications, then use right-click Open or Privacy & Security -> Open Anyway."
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$BG_DIR"
mkdir -p "$MODULE_CACHE_DIR"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

rm -f "$DMG_PATH" "$TEMP_DMG"

cp -R "$APP_PATH" "$STAGING_DIR/$APP_BUNDLE"
ditto --noextattr --noqtn "$BYPASS_SCRIPT_SRC" "$BYPASS_SCRIPT_DST"
chmod +x "$BYPASS_SCRIPT_DST"
xattr -c "$BYPASS_SCRIPT_DST" 2>/dev/null || true
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$INSTRUCTIONS_PATH" <<'TEXT'
Install GZWhisper:

1. Drag __APP_BUNDLE__ to Applications.
2. Eject this installer.
3. Open __APP_BUNDLE_NAME__ from Applications.

If macOS blocks launch (recommended fix):
1. In Applications, right-click __APP_BUNDLE_NAME__ and choose Open.
2. If needed, open System Settings -> Privacy & Security.
3. Scroll down and click Open Anyway for __APP_BUNDLE_NAME__.
4. Confirm with your Mac password or Touch ID.
5. Launch __APP_BUNDLE_NAME__ again.

Alternative fix:
Run Enable_GZWhisper.command once after the app has been copied to Applications.
TEXT
sed -i '' "s/__APP_BUNDLE__/$APP_BUNDLE/g; s/__APP_BUNDLE_NAME__/$APP_BUNDLE_NAME/g" "$INSTRUCTIONS_PATH"

cat > "$TERMINAL_FIX_PATH" <<'TEXT'
If __APP_BUNDLE_NAME__ is blocked:

Preferred fix from macOS settings:
1) Open System Settings -> Privacy & Security.
2) Scroll down and click Open Anyway for __APP_BUNDLE_NAME__.
3) Confirm with your Mac password or Touch ID.
4) Open __APP_BUNDLE_NAME__ again.

If Enable_GZWhisper.command is blocked too:

1) Open Terminal.
2) Run:
sudo xattr -dr com.apple.quarantine "/Applications/__APP_BUNDLE__"
open "/Applications/__APP_BUNDLE__"
TEXT
sed -i '' "s/__VOL_NAME__/$VOL_NAME/g; s/__APP_BUNDLE__/$APP_BUNDLE/g; s/__APP_BUNDLE_NAME__/$APP_BUNDLE_NAME/g" "$TERMINAL_FIX_PATH"

swift - <<'SWIFT' "$BG_PATH" "$APP_TITLE"
import AppKit
import Foundation

let out = CommandLine.arguments[1]
let appTitle = CommandLine.arguments[2]
let size = NSSize(width: 920, height: 560)
let image = NSImage(size: size)

image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.995, alpha: 1.0),
    NSColor(calibratedRed: 0.89, green: 0.93, blue: 0.98, alpha: 1.0)
])!
gradient.draw(in: rect, angle: -25)

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 34, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.42, alpha: 1.0),
]

let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1.0),
]

let noteAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.30, alpha: 1.0),
]

(appTitle).draw(at: NSPoint(x: 36, y: 500), withAttributes: titleAttrs)
("Перетащите приложение в папку Applications для установки").draw(at: NSPoint(x: 36, y: 468), withAttributes: subtitleAttrs)
("Если запуск заблокирован: System Settings -> Privacy & Security -> Open Anyway").draw(at: NSPoint(x: 36, y: 438), withAttributes: noteAttrs)
("Скрипт Enable_GZWhisper.command оставлен как запасной вариант").draw(at: NSPoint(x: 36, y: 418), withAttributes: noteAttrs)

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.12)
shadow.shadowBlurRadius = 6
shadow.shadowOffset = NSSize(width: 0, height: -1)
shadow.set()

let arrowStroke = NSBezierPath()
arrowStroke.lineWidth = 16
arrowStroke.lineCapStyle = .round
NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.90, alpha: 0.78).setStroke()
arrowStroke.move(to: NSPoint(x: 300, y: 270))
arrowStroke.curve(to: NSPoint(x: 620, y: 270), controlPoint1: NSPoint(x: 420, y: 270), controlPoint2: NSPoint(x: 540, y: 270))
arrowStroke.stroke()

let arrowHead = NSBezierPath()
NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.90, alpha: 0.90).setFill()
arrowHead.move(to: NSPoint(x: 640, y: 270))
arrowHead.line(to: NSPoint(x: 595, y: 300))
arrowHead.line(to: NSPoint(x: 595, y: 240))
arrowHead.close()
arrowHead.fill()

image.unlockFocus()

if let tiff = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: out))
}
SWIFT

hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname "$VOL_NAME" \
  -fs HFS+ \
  -format UDRW \
  "$TEMP_DMG" >/dev/null

DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" | awk '/Apple_HFS/ {print $1; exit}')"
if [[ -z "$DEVICE" ]]; then
  echo "Failed to attach temporary DMG"
  exit 1
fi

cleanup() {
  set +e
  if mount | grep -q "$MOUNT_POINT"; then
    hdiutil detach "$DEVICE" -quiet || true
  fi
}
trap cleanup EXIT

if ! osascript <<APPLESCRIPT
  tell application "Finder"
    tell disk "$VOL_NAME"
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set bounds of container window to {140, 140, 1060, 700}
      set opts to the icon view options of container window
      set arrangement of opts to not arranged
      set icon size of opts to 128
      set text size of opts to 14
      set background picture of opts to file ".background:background.png"
      set position of item "$APP_BUNDLE" of container window to {220, 270}
      set position of item "Applications" of container window to {700, 270}
      set position of item "$BYPASS_SCRIPT_NAME" of container window to {220, 430}
      set position of item "Install_Instructions.txt" of container window to {460, 430}
      set position of item "Run_If_Blocked.txt" of container window to {700, 430}
      close
      open
      update without registering applications
      delay 1
    end tell
  end tell
APPLESCRIPT
then
  echo "Warning: failed to customize DMG Finder layout; continuing with default layout." >&2
fi

sync
hdiutil detach "$DEVICE" -quiet
trap - EXIT

hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$TEMP_DMG"
rm -rf "$STAGING_DIR"

ditto --noextattr --noqtn "$BYPASS_SCRIPT_SRC" "$BUILD_DIR/$BYPASS_SCRIPT_NAME"
chmod +x "$BUILD_DIR/$BYPASS_SCRIPT_NAME"
xattr -c "$BUILD_DIR/$BYPASS_SCRIPT_NAME" 2>/dev/null || true

if [[ -n "$NOTARYTOOL_PROFILE" ]]; then
  if [[ "$APP_AUTHORITY" != Developer\ ID\ Application:* ]]; then
    echo "Skipping notarization: Developer ID Application signing is required."
  else
    echo "Submitting DMG for notarization with profile: $NOTARYTOOL_PROFILE"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait --timeout "$NOTARY_TIMEOUT"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  fi
fi

echo "Created DMG: $DMG_PATH"
echo "Standalone bypass script: $BUILD_DIR/$BYPASS_SCRIPT_NAME"
