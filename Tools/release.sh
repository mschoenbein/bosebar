#!/bin/zsh
# Builds release/BoseBar-<version>.dmg: the app plus a shortcut to /Applications.
#
# The app is only ad-hoc signed and NOT notarized by Apple, so macOS shows a
# warning on first launch (see "Download" in the README). Notarizing would need
# a "Developer ID Application" certificate.
#
# Usage: Tools/release.sh 1.0.0
set -euo pipefail

VERSION=${1:?usage: Tools/release.sh <version>}
cd "$(dirname "$0")/.."

APP=build/Build/Products/Release/BoseBar.app
OUT=release
DMG=$OUT/BoseBar-$VERSION.dmg
rm -rf "$OUT" && mkdir -p "$OUT/dmg"

xcodegen generate
xcodebuild -project BoseBar.xcodeproj -scheme BoseBar -configuration Release \
    -derivedDataPath build MARKETING_VERSION="$VERSION" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build | grep -E "error|BUILD" # universal: Apple Silicon + Intel

cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "BoseBar" -srcfolder "$OUT/dmg" -ov -format UDZO "$DMG" >/dev/null 2>&1
rm -rf "$OUT/dmg"
echo "Done: $DMG"
