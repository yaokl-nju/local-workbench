#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for file in Sources/Core.swift Sources/Storage.swift Sources/Store.swift Sources/Views.swift Sources/Main.swift Sources/Ask.swift Resources/Info.plist; do test -f "$file"; done
xcrun --find swiftc
plutil -lint Resources/Info.plist
echo '源码、编译器、App 元数据检查通过；不需要网络或第三方依赖。'
