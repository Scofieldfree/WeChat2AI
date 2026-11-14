#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${WECHAT2AI_APP_SOURCE:-$PWD/build/WeChat2AI.app}"
REPLACE=false
if [[ "${1:-}" == "--replace" ]]; then REPLACE=true
elif [[ -n "${1:-}" ]]; then printf 'Usage: install-local.sh [--replace]\n' >&2; exit 1; fi
if [[ ! -d "$SOURCE" ]]; then printf 'Run scripts/build.sh first.\n' >&2; exit 1; fi
NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$SOURCE/Contents/Info.plist")
IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")
if [[ "$NAME" != WeChat2AI ]]; then
  printf 'Unexpected application name. No files were changed.\n' >&2; exit 1
fi
if [[ "$IDENTIFIER" != local.scofield.wechat2ai ]]; then
  printf 'Unexpected application identifier. No files were changed.\n' >&2; exit 1
fi
DEST="$HOME/Applications/$NAME.app"
PREVIOUS=""
if [[ -e "$DEST" ]]; then PREVIOUS="$DEST"; fi
if [[ -n "$PREVIOUS" && "$REPLACE" != true ]]; then
  printf 'Already exists: %s\nQuit WeChat2AI, then use --replace to back up and upgrade.\n' "$PREVIOUS" >&2
  exit 1
fi
if pgrep -x WeChat2AI >/dev/null; then printf 'Quit WeChat2AI before installing. No files were changed.\n' >&2; exit 1; fi
mkdir -p "$HOME/Applications"
STAGING=$(mktemp -d "$HOME/Applications/.wechat2ai-install.XXXXXX")
BACKUP=""
BACKUP_APP=""
INSTALLED=false
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
cleanup() {
  result=$?
  if [[ "$result" != 0 && -n "$BACKUP_APP" && -d "$BACKUP_APP" ]]; then
    if [[ "$INSTALLED" == true && -d "$DEST" ]]; then
      "$LSREGISTER" -u "$DEST" || true
      pluginkit -r "$DEST/Contents/PlugIns/WeChat2AIShare.appex" || true
      mv "$DEST" "$STAGING/failed-$NAME.app" || true
    fi
    if [[ ! -e "$PREVIOUS" ]]; then
      mv "$BACKUP_APP" "$PREVIOUS" || true
      "$LSREGISTER" -f "$PREVIOUS" || true
      pluginkit -a "$PREVIOUS/Contents/PlugIns/WeChat2AIShare.appex" || true
      pluginkit -e use -i local.scofield.wechat2ai.share || true
    fi
    printf 'Install did not complete. Previous app restoration attempted; staging: %s\n' "$STAGING" >&2
  fi
  rmdir "$STAGING" 2>/dev/null || true
  return "$result"
}
trap cleanup EXIT
/usr/bin/ditto "$SOURCE" "$STAGING/$NAME.app"
codesign --verify --deep --strict "$STAGING/$NAME.app"
if [[ -n "$PREVIOUS" ]]; then
  BACKUPS="$HOME/Library/Application Support/WeChat2AI/AppBackups"
  mkdir -p "$BACKUPS"
  BACKUP=$(mktemp -d "$BACKUPS/$(date +%Y%m%d-%H%M%S)-XXXXXX")
  BACKUP_APP="$BACKUP/$(basename "$PREVIOUS")"
  "$LSREGISTER" -u "$PREVIOUS" || true
  pluginkit -r "$PREVIOUS/Contents/PlugIns/WeChat2AIShare.appex" || true
  mv "$PREVIOUS" "$BACKUP_APP"
fi
mv "$STAGING/$NAME.app" "$DEST"
INSTALLED=true
codesign --verify --deep --strict "$DEST"
"$LSREGISTER" -f "$DEST"
pluginkit -r "$SOURCE/Contents/PlugIns/WeChat2AIShare.appex" || true
pluginkit -a "$DEST/Contents/PlugIns/WeChat2AIShare.appex"
pluginkit -e use -i local.scofield.wechat2ai.share
open "$DEST"
printf 'Installed: %s\n' "$DEST"
if [[ -n "$BACKUP_APP" ]]; then printf 'Previous app backup: %s\n' "$BACKUP_APP"; fi
