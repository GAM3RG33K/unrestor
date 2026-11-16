#!/bin/bash
# Build Unrestor.app and a DMG from source. No Apple Developer account needed:
# the app is ad-hoc signed, so macOS asks users to approve it on first launch
# (see docs/DISTRIBUTION.md). Output goes to dist/.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/UnrestorCore/Protocol.swift)"
[ -n "$VERSION" ] || { echo "error: could not read the version" >&2; exit 1; }

echo "==> Building $VERSION (universal)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

OUT="$PWD/dist"
APP="$OUT/Unrestor.app"
rm -rf "$APP" "$OUT/Unrestor-$VERSION.dmg"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources/Legal"

cp "$BIN/UnrestorApp" "$APP/Contents/MacOS/Unrestor"
cp "$BIN/unrestor" "$APP/Contents/Helpers/unrestor"
cp "$BIN/unrestor-daemon" "$APP/Contents/Helpers/unrestor-daemon"
cp LICENSE NOTICE "$APP/Contents/Resources/Legal/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Unrestor</string>
	<key>CFBundleName</key><string>Unrestor</string>
	<key>CFBundleExecutable</key><string>Unrestor</string>
	<key>CFBundleIdentifier</key><string>app.unrestor</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
for helper in "$APP/Contents/Helpers/unrestor" "$APP/Contents/Helpers/unrestor-daemon"; do
    /usr/bin/codesign --force --sign - "$helper"
done
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

echo "==> Building DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Unrestor.app"
ln -s /Applications "$STAGE/Applications"
/usr/bin/hdiutil create -volname "Unrestor" -srcfolder "$STAGE" -ov -format UDZO \
    "$OUT/Unrestor-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

( cd "$OUT" && /usr/bin/shasum -a 256 "Unrestor-$VERSION.dmg" | tee "Unrestor-$VERSION.dmg.sha256" )
echo "Built $APP and $OUT/Unrestor-$VERSION.dmg"
