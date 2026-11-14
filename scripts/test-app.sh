#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
APP_SOURCES=()
for source in App/*.swift; do
  [[ "$source" == "App/App.swift" ]] || APP_SOURCES+=("$source")
done
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -I Sources/CZlib \
  Sources/WeChat2AICore/*.swift "${APP_SOURCES[@]}" Tests/AppStateTests/Run.swift \
  -o build/AppStateTests -framework AppKit -framework SwiftUI -framework Combine
build/AppStateTests "$@"
