#!/bin/bash
# Signs with Developer ID, notarizes and staples. Requires a "Developer ID Application" certificate and a
# notarytool keychain profile:  xcrun notarytool store-credentials AWDLess --apple-id you@example.com --team-id KEYC53CXGS
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/AWDLess.app
IDENTITY="${IDENTITY:-Developer ID Application}"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/AWDLessHelper"
codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements AWDLess/AWDLess.entitlements "$APP"
ditto -c -k --keepParent "$APP" build/AWDLess.zip
xcrun notarytool submit build/AWDLess.zip --keychain-profile AWDLess --wait
xcrun stapler staple "$APP"
hdiutil create -volname AWDLess -srcfolder "$APP" -ov -format UDZO build/AWDLess.dmg
echo "notarized: build/AWDLess.dmg"
