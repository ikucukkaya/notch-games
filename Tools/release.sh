#!/bin/bash
# Builds, signs, notarizes and packages NotchBasket for direct distribution.
#
# Prerequisites (one-time, see RELEASE.md):
#   1. A "Developer ID Application" certificate in your keychain.
#   2. Notary credentials stored under a keychain profile:
#        xcrun notarytool store-credentials notchbasket \
#          --apple-id you@example.com --team-id TEAMID --password app-specific-pw
#
# Usage: Tools/release.sh [keychain-profile]   (default profile: notchbasket)
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${1:-notchbasket}"
VERSION=$(grep -m1 "MARKETING_VERSION" NotchBasket.xcodeproj/project.pbxproj | sed 's/[^0-9.]//g')
DIST="dist"
ARCHIVE="$DIST/NotchBasket.xcarchive"
APP="$DIST/export/NotchBasket.app"
DMG="$DIST/NotchBasket-$VERSION.dmg"

rm -rf "$DIST" && mkdir -p "$DIST"

echo "==> Archiving $VERSION"
xcodebuild archive \
  -project NotchBasket.xcodeproj -scheme NotchBasket \
  -destination 'platform=macOS' -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Automatic -quiet

echo "==> Exporting with Developer ID"
cat > "$DIST/export-options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$DIST/export-options.plist" \
  -exportPath "$DIST/export" -quiet

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier" | head -3

echo "==> Building DMG"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "NotchBasket" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG" -quiet

echo "==> Notarizing (waits for Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"

echo "==> Gatekeeper check"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true

echo ""
echo "Done: $DMG"
