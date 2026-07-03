#!/usr/bin/env bash
set -euo pipefail

# Regenerates Resources/AppIcon.icns from assets/app-icon.svg.
# Requires rsvg-convert (brew install librsvg) and iconutil (macOS).
# The .icns is committed so packaging needs no SVG toolchain.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/assets/app-icon.svg"
OUT="$ROOT/Resources/AppIcon.icns"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found — brew install librsvg" >&2; exit 1; }

tmp="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$tmp"
trap 'rm -rf "$(dirname "$tmp")"' EXIT

render() { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$tmp/$2"; }

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$tmp" -o "$OUT"
echo "✓ wrote ${OUT#"$ROOT"/}"
