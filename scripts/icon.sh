#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache build/AppIcon.iconset
xcrun swiftc -module-cache-path "$PWD/build/module-cache" scripts/Icon.swift -o build/MakeIcon
build/MakeIcon "$PWD/build/AppIcon.iconset"
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
