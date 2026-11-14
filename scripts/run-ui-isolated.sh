#!/bin/bash
# Create synthetic data at explicit temporary paths; never install/register this host.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x build/AppStateTests || ! -x build/WeChat2AI.app/Contents/MacOS/WeChat2AI ]]; then
  printf 'Run bash scripts/test-app.sh and bash scripts/build.sh first.\n' >&2
  exit 1
fi
HOST_ROOT=$(mktemp -d "$PWD/build/ui-host.XXXXXX")
build/AppStateTests --prepare-ui-host "$HOST_ROOT" "$@"
# A distinct bundle ID avoids interacting with the user's running daily application.
HOST_APP="$PWD/build/WeChat2AI-UIHost.app"
mkdir -p "$HOST_APP/Contents/MacOS" "$HOST_APP/Contents/Resources"
cp build/WeChat2AI.app/Contents/MacOS/WeChat2AI "$HOST_APP/Contents/MacOS/WeChat2AI"
cp build/WeChat2AI.app/Contents/Resources/WeChat2AI.icns "$HOST_APP/Contents/Resources/WeChat2AI.icns"
cp Resources/Brand/*.svg "$HOST_APP/Contents/Resources/"
cp Resources/App-Info.plist "$HOST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.scofield.wechat2ai.ui-test' "$HOST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName WeChat2AI UI Host' "$HOST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName WeChat2AI UI Host' "$HOST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleDocumentTypes' "$HOST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :UTExportedTypeDeclarations' "$HOST_APP/Contents/Info.plist"
codesign --force --sign - "$HOST_APP"
printf 'Isolated data: %s\n' "$HOST_ROOT"
exec "$HOST_APP/Contents/MacOS/WeChat2AI" --ui-test-root "$HOST_ROOT" "$@"
