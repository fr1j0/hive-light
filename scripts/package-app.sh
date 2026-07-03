#!/usr/bin/env bash
set -euo pipefail

# Builds a release binary and lays it out as Claude Light.app, bundling the
# claude-light-hook helper at Contents/MacOS/ so the installer's hook path resolves.

APP="dist/Claude Light.app"

swift build -c release --product ClaudeLightApp
swift build -c release --product claude-light-hook

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/ClaudeLightApp          "$APP/Contents/MacOS/ClaudeLightApp"
cp .build/release/claude-light-hook       "$APP/Contents/MacOS/claude-light-hook"
cp Resources/Info.plist                   "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns                 "$APP/Contents/Resources/AppIcon.icns"

echo "Built $APP"
echo ""
echo "Contents:"
find "$APP" -not -type d | sort
