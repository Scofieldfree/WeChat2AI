#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc -swift-version 5 -I Sources/CZlib Sources/WeChat2AICore/*.swift Tests/WeChat2AICoreTests/*.swift Tests/Run.swift -o build/WeChat2AICoreTests
build/WeChat2AICoreTests
