#!/bin/bash
# Generates the Xcode project and builds a Release app into build/.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project AWDLess.xcodeproj -scheme AWDLess -configuration Release -derivedDataPath build/DerivedData build | tail -3
rm -rf build/AWDLess.app
cp -R build/DerivedData/Build/Products/Release/AWDLess.app build/
codesign -dv --verbose=2 build/AWDLess.app 2>&1 | grep -E "Authority|TeamIdentifier|Identifier=" | head -4
echo "built: $(pwd)/build/AWDLess.app"
