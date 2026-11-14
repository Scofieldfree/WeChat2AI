#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MASTER="Resources/Icon/app-icon.png"
ICONSET="build/WeChat2AI.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$MASTER" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$MASTER" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/WeChat2AI.icns
