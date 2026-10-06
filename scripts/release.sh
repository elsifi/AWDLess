#!/bin/bash
# Builds, signs, notarizes (when credentials exist), packages a .dmg and publishes a GitHub release.
# Usage: scripts/release.sh 0.1.0
# Needs: xcodegen, Xcode, gh. For a notarized build: a "Developer ID Application" certificate in the keychain and a
# notarytool keychain profile named AWDLess (xcrun notarytool store-credentials AWDLess --key AuthKey.p8 --key-id KEYID --issuer ISSUER).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?version, e.g. 0.1.0}"
APP=build/AWDLess.app

sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
BUILD_NO=$(( $(git rev-list --count HEAD) ))
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NO\"/" project.yml
xcodegen generate --quiet

DEV_ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
if [ -n "$DEV_ID" ]; then
  echo "Signing with: $DEV_ID"
  xcodebuild -project AWDLess.xcodeproj -scheme AWDLess -configuration Release -derivedDataPath build/DerivedData \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEV_ID" OTHER_CODE_SIGN_FLAGS="--timestamp" build | grep -E "error:|BUILD"
else
  echo "No Developer ID certificate found; signing with development identity (Gatekeeper will warn)."
  xcodebuild -project AWDLess.xcodeproj -scheme AWDLess -configuration Release -derivedDataPath build/DerivedData build | grep -E "error:|BUILD"
fi
rm -rf "$APP"; cp -R build/DerivedData/Build/Products/Release/AWDLess.app "$APP"
codesign --verify --deep --strict "$APP"

rm -f build/AWDLess-$VERSION.dmg build/AWDLess-$VERSION.zip
mkdir -p build/dmg && rm -rf build/dmg/* && cp -R "$APP" build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname "AWDLess $VERSION" -srcfolder build/dmg -ov -format UDZO -quiet build/AWDLess-$VERSION.dmg
ditto -c -k --keepParent "$APP" build/AWDLess-$VERSION.zip

if [ -n "$DEV_ID" ] && xcrun notarytool history --keychain-profile AWDLess >/dev/null 2>&1; then
  codesign --force --options runtime --timestamp --sign "$DEV_ID" build/AWDLess-$VERSION.dmg
  xcrun notarytool submit build/AWDLess-$VERSION.dmg --keychain-profile AWDLess --wait
  xcrun stapler staple build/AWDLess-$VERSION.dmg
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" build/AWDLess-$VERSION.zip
  spctl -a -vv -t install "$APP" 2>&1 | tail -2
  NOTE="Notarized by Apple."
else
  NOTE="Not notarized: macOS will show 'could not verify'; use System Settings › Privacy & Security › Open Anyway."
fi

git add project.yml && git commit -qm "Release $VERSION" || true
git tag -f "v$VERSION" && git push -q origin main --tags
gh release create "v$VERSION" build/AWDLess-$VERSION.dmg build/AWDLess-$VERSION.zip \
  --title "AWDLess $VERSION" --notes "$(printf 'See https://elsifi.github.io/AWDLess/ for what it does.\n\n%s\n\nRequires macOS 14 or later. Drag to Applications, then click the menu bar icon and Install the helper.' "$NOTE")"
echo "released v$VERSION"
