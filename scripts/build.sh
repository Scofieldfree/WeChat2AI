#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/version.sh check
APP="$PWD/build/WeChat2AI.app"
EXT="$APP/Contents/PlugIns/WeChat2AIShare.appex"
# Only generated output is replaced; never package leftovers from an earlier build.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS" "$EXT/Contents/Resources"
./scripts/build-icon.sh
cp build/WeChat2AI.icns "$APP/Contents/Resources/WeChat2AI.icns"
cp Resources/Brand/*.svg "$APP/Contents/Resources/"
cp build/WeChat2AI.icns "$EXT/Contents/Resources/WeChat2AI.icns"
cp -X LICENSE NOTICE.md "$APP/Contents/Resources/"
cp -X LICENSE NOTICE.md "$EXT/Contents/Resources/"
SDK="$(xcrun --show-sdk-path)"
TARGET="$(uname -m)-apple-macosx13.0"
xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$TARGET" -I Sources/CZlib \
  Sources/WeChat2AICore/*.swift App/*.swift -o "$APP/Contents/MacOS/WeChat2AI" -framework AppKit -framework SwiftUI -framework Combine
xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$TARGET" -parse-as-library \
  -application-extension -module-name WeChat2AIShare Sources/WeChat2AICore/SafeFiles.swift Sources/WeChat2AICore/IntakeQueue.swift ShareExtension/*.swift \
  -Xlinker -e -Xlinker _NSExtensionMain -o "$EXT/Contents/MacOS/WeChat2AIShare" -framework AppKit
cp Resources/App-Info.plist "$APP/Contents/Info.plist"
cp Resources/Share-Info.plist "$EXT/Contents/Info.plist"
# Remove machine-specific extended attributes before signing the generated bundle.
xattr -cr "$APP"
codesign --force --sign "${SIGN_IDENTITY:--}" --entitlements Resources/Share.entitlements "$EXT"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
