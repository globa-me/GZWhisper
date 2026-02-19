#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Resources"
OUT_PNG="$OUT_DIR/AppIcon.png"
OUT_ICNS="$OUT_DIR/AppIcon.icns"
MODULE_CACHE_DIR="$ROOT_DIR/build/module-cache"
TMP_DIR="$ROOT_DIR/build/icns-build"

mkdir -p "$OUT_DIR" "$MODULE_CACHE_DIR" "$TMP_DIR"
export SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"

swift - <<'SWIFT' "$OUT_PNG"
import AppKit
import Foundation

let outputPath = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

let roundedRect = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.03, green: 0.52, blue: 0.74, alpha: 1.0),
    NSColor(calibratedRed: 0.04, green: 0.26, blue: 0.56, alpha: 1.0)
])!
gradient.draw(in: roundedRect, angle: -40)

NSColor(calibratedWhite: 1.0, alpha: 0.25).setStroke()
for i in 0..<5 {
    let y = 260 + CGFloat(i) * 90
    let wave = NSBezierPath()
    wave.lineWidth = 18
    wave.move(to: NSPoint(x: 150, y: y))
    wave.curve(to: NSPoint(x: 874, y: y), controlPoint1: NSPoint(x: 300, y: y + 80), controlPoint2: NSPoint(x: 700, y: y - 80))
    wave.stroke()
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 330, weight: .heavy),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
]

"GZ".draw(in: NSRect(x: 0, y: 290, width: 1024, height: 360), withAttributes: attrs)

image.unlockFocus()

if let tiffData = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
}
SWIFT

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

sips -z 16 16 "$OUT_PNG" --out "$TMP_DIR/icp4.png" >/dev/null
sips -z 32 32 "$OUT_PNG" --out "$TMP_DIR/icp5.png" >/dev/null
sips -z 64 64 "$OUT_PNG" --out "$TMP_DIR/icp6.png" >/dev/null
sips -z 32 32 "$OUT_PNG" --out "$TMP_DIR/ic11.png" >/dev/null
sips -z 64 64 "$OUT_PNG" --out "$TMP_DIR/ic12.png" >/dev/null
sips -z 128 128 "$OUT_PNG" --out "$TMP_DIR/ic07.png" >/dev/null
sips -z 256 256 "$OUT_PNG" --out "$TMP_DIR/ic08.png" >/dev/null
sips -z 512 512 "$OUT_PNG" --out "$TMP_DIR/ic09.png" >/dev/null
sips -z 1024 1024 "$OUT_PNG" --out "$TMP_DIR/ic10.png" >/dev/null
sips -z 256 256 "$OUT_PNG" --out "$TMP_DIR/ic13.png" >/dev/null
sips -z 512 512 "$OUT_PNG" --out "$TMP_DIR/ic14.png" >/dev/null

python3 - <<'PY' "$TMP_DIR" "$OUT_ICNS"
import struct
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])
out_file = Path(sys.argv[2])

entries = [
    ("icp4", "icp4.png"),
    ("icp5", "icp5.png"),
    ("icp6", "icp6.png"),
    ("ic11", "ic11.png"),
    ("ic12", "ic12.png"),
    ("ic07", "ic07.png"),
    ("ic08", "ic08.png"),
    ("ic09", "ic09.png"),
    ("ic10", "ic10.png"),
    ("ic13", "ic13.png"),
    ("ic14", "ic14.png"),
]

payload = bytearray()
for icon_type, filename in entries:
    data = (tmp_dir / filename).read_bytes()
    payload.extend(icon_type.encode("ascii"))
    payload.extend(struct.pack(">I", len(data) + 8))
    payload.extend(data)

result = bytearray(b"icns")
result.extend(struct.pack(">I", len(payload) + 8))
result.extend(payload)
out_file.write_bytes(result)
PY

rm -rf "$TMP_DIR"

echo "Icon generated: $OUT_PNG"
echo "ICNS generated: $OUT_ICNS"
