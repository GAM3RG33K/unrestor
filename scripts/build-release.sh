#!/bin/bash
# Build, sign, notarize, and package Unrestor.dmg, then print its SHA-256 and
# the Homebrew cask stanza. Run from a clean checkout. Publishes nothing.
#
# Required environment:
#   UNRESTOR_TEAM_ID        Apple Developer Team ID
#   UNRESTOR_NOTARY_PROFILE name of a stored `xcrun notarytool` keychain profile
#                           (create once: xcrun notarytool store-credentials NAME)
# The signing identity "Developer ID Application" for that team must be in your
# keychain.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
: "${UNRESTOR_TEAM_ID:?set UNRESTOR_TEAM_ID}"
: "${UNRESTOR_NOTARY_PROFILE:?set UNRESTOR_NOTARY_PROFILE}"

if [ -n "$(git status --porcelain)" ]; then
    echo "error: the working tree is not clean; commit or stash first." >&2
    exit 1
fi

command -v xcodegen >/dev/null || { echo "error: brew install xcodegen" >&2; exit 1; }

# The generated project and DerivedData stay out of the repo.
WORK="$(mktemp -d /private/tmp/unrestor-release.XXXXXX)"
OUT="$PWD/dist"
mkdir -p "$OUT"

VERSION="$(/usr/bin/awk '/MARKETING_VERSION:/ { print $2 }' project.yml)"
DMG="$OUT/Unrestor-$VERSION.dmg"

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Archiving Release $VERSION"
xcodebuild -project Unrestor.xcodeproj -scheme Unrestor -configuration Release \
    -derivedDataPath "$WORK/derived" \
    -archivePath "$WORK/Unrestor.xcarchive" \
    DEVELOPMENT_TEAM="$UNRESTOR_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    archive | /usr/bin/tail -n 3

APP="$WORK/Unrestor.xcarchive/Products/Applications/Unrestor.app"
[ -d "$APP" ] || { echo "error: archive produced no app" >&2; exit 1; }

echo "==> Verifying signature"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/codesign -dv "$APP" 2>&1 | /usr/bin/grep -E "Authority=Developer ID|TeamIdentifier=$UNRESTOR_TEAM_ID" >/dev/null \
    || { echo "error: app is not Developer ID signed by $UNRESTOR_TEAM_ID" >&2; exit 1; }

echo "==> Building DMG"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/Unrestor.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
/usr/bin/hdiutil create -volname "Unrestor" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
/usr/bin/codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "==> Notarizing (this takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$UNRESTOR_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose "$DMG"

SHA="$(/usr/bin/shasum -a 256 "$DMG" | /usr/bin/awk '{ print $1 }')"
echo
echo "Built:   $DMG"
echo "SHA-256: $SHA"
echo
echo "Next: attach the DMG to a GitHub release, then update the cask:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA\""
rm -rf "$WORK"
