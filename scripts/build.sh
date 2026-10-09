#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache dist/本地工作台.app/Contents/MacOS dist/本地工作台.app/Contents/Resources
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -O -module-cache-path "$PWD/build/module-cache" Sources/*.swift -o build/LocalNotes-arm64
xcrun swiftc -parse-as-library -swift-version 5 -target x86_64-apple-macos14.0 -O -module-cache-path "$PWD/build/module-cache" Sources/*.swift -o build/LocalNotes-x86_64
lipo -create build/LocalNotes-arm64 build/LocalNotes-x86_64 -output dist/本地工作台.app/Contents/MacOS/LocalNotes
cp Resources/AppIcon.icns dist/本地工作台.app/Contents/Resources/AppIcon.icns
cp Resources/Info.plist dist/本地工作台.app/Contents/Info.plist
printf 'APPL????' > dist/本地工作台.app/Contents/PkgInfo
codesign --force --sign - dist/本地工作台.app
codesign --verify --deep --strict dist/本地工作台.app
echo "已构建：$PWD/dist/本地工作台.app"
