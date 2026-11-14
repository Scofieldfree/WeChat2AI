#!/bin/bash
# Build and archive without installing, registering, or launching the application.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/version.sh check
bash scripts/build.sh
APP="$PWD/build/WeChat2AI.app"
VERSION=$(bash scripts/version.sh version)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
ARCH=$(uname -m)
case "$ARCH" in arm64|x86_64) ;; *) printf 'Unsupported release architecture: %s\n' "$ARCH" >&2; exit 1 ;; esac
mkdir -p build/releases
RELEASE=$(mktemp -d "$PWD/build/releases/WeChat2AI-$VERSION-build$BUILD-$ARCH.XXXXXX")
ARCHIVE="$RELEASE/WeChat2AI-$VERSION-build$BUILD-$ARCH.zip"
codesign --verify --deep --strict "$APP"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$ARCHIVE"
(
  cd "$RELEASE"
  shasum -a 256 "$(basename "$ARCHIVE")" > SHA256SUMS.txt
)
printf 'Packaged: %s\nChecksums: %s/SHA256SUMS.txt\n' "$ARCHIVE" "$RELEASE"
