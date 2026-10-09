#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -x dist/本地工作台.app/Contents/MacOS/LocalNotes
test -s dist/本地工作台.app/Contents/Resources/AppIcon.icns
lipo dist/本地工作台.app/Contents/MacOS/LocalNotes -verify_arch arm64 x86_64
plutil -lint dist/本地工作台.app/Contents/Info.plist
test "$(plutil -extract CFBundleName raw dist/本地工作台.app/Contents/Info.plist)" = '本地工作台'
test "$(plutil -extract CFBundleDisplayName raw dist/本地工作台.app/Contents/Info.plist)" = '本地工作台'
codesign --verify --deep --strict dist/本地工作台.app
file dist/本地工作台.app/Contents/MacOS/LocalNotes
echo 'App 可执行文件、元数据和本机签名检查通过。'
