#!/usr/bin/env bash
set -euo pipefail

# Builds a release binary and lays it out as Hive Light.app, bundling the
# hive-light-hook helper at Contents/MacOS/ so the installer's hook path resolves.

APP="dist/Hive Light.app"

# --build-system native: Xcode 27's default SwiftPM backend (swiftbuild) stamps
# the binary's linked SDK as the deployment target (13.0) instead of the real
# SDK. AppKit gates modern window chrome on that stamp, so the MenuBarExtra
# panel loses its rounded corners. native is deprecated — when it goes away,
# the check below is what tells us swiftbuild still mis-stamps.
swift build -c release --product HiveLightApp --build-system native
swift build -c release --product hive-light-hook --build-system native

# The mis-stamp's signature is "stamp != the SDK actually built against", so
# compare those (by major) — not a fixed floor: CI's macos-14 runner honestly
# stamps 14.x, and a hard-coded minimum would fail every release there.
SDK_STAMP="$(otool -l .build/release/HiveLightApp | awk '/LC_BUILD_VERSION/{f=1} f && $1=="sdk"{print $2; exit}')"
SDK_REAL="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${SDK_STAMP%%.*}" != "${SDK_REAL%%.*}" ]]; then
    echo "error: HiveLightApp is stamped with SDK $SDK_STAMP but was built against SDK $SDK_REAL — the panel would render with legacy square chrome." >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/HiveLightApp          "$APP/Contents/MacOS/HiveLightApp"
cp .build/release/hive-light-hook       "$APP/Contents/MacOS/hive-light-hook"
cp Resources/Info.plist                   "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns                 "$APP/Contents/Resources/AppIcon.icns"

# Notification Center banners resolve the app icon only through a compiled
# asset catalog named by CFBundleIconName — the .icns alone leaves banners
# blank (#59). Derive the catalog from the committed .icns so packaging
# still needs no SVG toolchain.
CATALOG_TMP="$(mktemp -d)"
trap 'rm -rf "$CATALOG_TMP"' EXIT
ICONSET="$CATALOG_TMP/AppIcon.iconset"
APPICONSET="$CATALOG_TMP/Assets.xcassets/AppIcon.appiconset"
iconutil -c iconset "Resources/AppIcon.icns" -o "$ICONSET"
mkdir -p "$APPICONSET"
cp "$ICONSET"/*.png "$APPICONSET/"
python3 - "$APPICONSET" <<'PY'
import json, os, re, sys
appiconset = sys.argv[1]
images = []
for name in sorted(os.listdir(appiconset)):
    m = re.match(r'icon_(\d+)x\d+(@2x)?\.png$', name)
    if not m:
        continue
    images.append({
        "filename": name,
        "idiom": "mac",
        "scale": "2x" if m.group(2) else "1x",
        "size": f"{m.group(1)}x{m.group(1)}",
    })
with open(os.path.join(appiconset, "Contents.json"), "w") as f:
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
PY
xcrun actool --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 13.0 \
    --app-icon AppIcon --output-partial-info-plist "$CATALOG_TMP/partial.plist" \
    "$CATALOG_TMP/Assets.xcassets" > /dev/null

echo "Built $APP"
echo ""
echo "Contents:"
find "$APP" -not -type d | sort
