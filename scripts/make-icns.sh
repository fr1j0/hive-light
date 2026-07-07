#!/usr/bin/env bash
set -euo pipefail

# Regenerates Resources/AppIcon.icns from assets/app-icon.png — the app-icon
# artwork that is also the README hero. The artwork is scaled to fit Apple's
# icon grid (an 824px box centered on a transparent 1024px canvas) so it
# sits at the same size as neighboring Dock icons.
# Requires only the Xcode command-line tools (swift, sips, iconutil).
# The .icns is committed so packaging needs no extra toolchain.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/assets/app-icon.png"
OUT="$ROOT/Resources/AppIcon.icns"

[ -f "$SRC" ] || { echo "icon source not found: $SRC" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Compose the 1024px master: source scaled to fit the 824px grid box,
# centered, transparent margins.
swift - "$SRC" "$tmp/master.png" <<'SWIFT'
import AppKit
let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
guard let data = FileManager.default.contents(atPath: src),
      let image = NSBitmapImageRep(data: data) else {
    fatalError("cannot read \(CommandLine.arguments[1])")
}
let canvas = 1024, box = 824.0
let w = Double(image.pixelsWide), h = Double(image.pixelsHigh)
let scale = box / max(w, h)
let dw = w * scale, dh = h * scale
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: (Double(canvas) - dw) / 2, y: (Double(canvas) - dh) / 2,
                      width: dw, height: dh))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dst))
SWIFT

ICONSET="$tmp/AppIcon.iconset"
mkdir -p "$ICONSET"

render() { sips -z "$1" "$1" "$tmp/master.png" --out "$ICONSET/$2" >/dev/null; }

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
cp "$tmp/master.png" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$OUT"
echo "✓ wrote ${OUT#"$ROOT"/}"
