#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache test-results
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/Storage.swift Sources/Store.swift Sources/Ask.swift Sources/Views.swift Tests/CoreTests.swift -o build/CoreTests
build/CoreTests | tee test-results/unit-tests.txt
