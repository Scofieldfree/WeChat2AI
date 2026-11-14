#!/bin/bash
# Canonical release identity; all operations are local and never publish or tag.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'Version check failed: %s\n' "$*" >&2; exit 1; }
usage() {
  printf 'Usage: bash scripts/version.sh check|version|build|base|tag|name|channel\n       bash scripts/version.sh set VERSION BUILD\n       bash scripts/version.sh check-tag TAG [origin/main|main]\n' >&2
  exit 1
}
validate_version() {
  local pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)\.[1-9][0-9]*)?$'
  [[ "$1" =~ $pattern ]] || fail 'Expected X.Y.Z or X.Y.Z-alpha.N / beta.N / rc.N, without leading zeros.'
}
validate_build() {
  [[ "$1" =~ ^[1-9][0-9]{0,3}$ ]] || fail 'Build must be an integer from 1 to 9999.'
}
VERSION=$(plutil -extract version raw -expect string -o - version.json) || fail 'Cannot read version.json version.'
BUILD=$(plutil -extract build raw -expect integer -o - version.json) || fail 'Cannot read version.json build.'
validate_version "$VERSION"
validate_build "$BUILD"
BASE=${VERSION%%-*}
PLISTS=(Resources/App-Info.plist Resources/Share-Info.plist)

check() {
  local plist actual_version actual_build
  for plist in "${PLISTS[@]}"; do
    actual_version=$(plutil -extract CFBundleShortVersionString raw -expect string -o - "$plist")
    actual_build=$(plutil -extract CFBundleVersion raw -expect string -o - "$plist")
    [[ "$actual_version" == "$BASE" && "$actual_build" == "$BUILD" ]] || fail "$plist must match version.json ($BASE / $BUILD)."
  done
}

COMMAND=${1:-check}
case "$COMMAND" in
  set)
    [[ $# == 3 ]] || usage
    validate_version "$2"; validate_build "$3"
    if [[ "$2" != "$VERSION" || "$3" != "$BUILD" ]]; then
      (( $3 > BUILD )) || fail 'A changed release identity must increase the build number.'
    fi
    # Prepare all output first; source files remain reviewable before committing.
    mkdir -p build
    STAGING=$(mktemp -d "$PWD/build/version.XXXXXX")
    trap 'rm -rf "$STAGING"' EXIT
    for plist in "${PLISTS[@]}"; do
      cp -p "$plist" "$STAGING/$(basename "$plist")"
      plutil -replace CFBundleShortVersionString -string "${2%%-*}" "$STAGING/$(basename "$plist")"
      plutil -replace CFBundleVersion -string "$3" "$STAGING/$(basename "$plist")"
    done
    printf '{\n  "version": "%s",\n  "build": %s\n}\n' "$2" "$3" > "$STAGING/version.json"
    for plist in "${PLISTS[@]}"; do cp -p "$STAGING/$(basename "$plist")" "$plist"; done
    cp "$STAGING/version.json" version.json
    VERSION=$2; BUILD=$3; BASE=${VERSION%%-*}; check
    printf 'Version set to %s / build %s. Review and commit the three metadata files together.\n' "$VERSION" "$BUILD"
    ;;
  check-tag)
    [[ $# -ge 2 && $# -le 3 ]] || usage
    check
    TAG=$2; MAIN_REF=${3:-origin/main}
    case "$MAIN_REF" in main|origin/main) ;; *) fail 'Only main or origin/main is an allowed release source.' ;; esac
    [[ "$TAG" == "v$VERSION" ]] || fail 'Tag must equal v + version.json version.'
    [[ "$(git cat-file -t "refs/tags/$TAG" 2>/dev/null || true)" == tag ]] || fail 'An existing annotated tag is required.'
    TAG_COMMIT=$(git rev-parse --verify "refs/tags/$TAG^{commit}")
    [[ "$(git rev-parse --verify HEAD)" == "$TAG_COMMIT" ]] || fail 'Check out the tagged commit before validating a release.'
    git ls-files --error-unmatch version.json "${PLISTS[@]}" >/dev/null 2>&1 || fail 'Version metadata must be tracked in the tagged source.'
    git diff --quiet && git diff --cached --quiet || fail 'Tracked source changes must be committed before a release.'
    git rev-parse --verify "$MAIN_REF^{commit}" >/dev/null 2>&1 || fail 'Main ref missing; fetch full history and main before checking.'
    git merge-base --is-ancestor "$TAG_COMMIT" "$MAIN_REF" || fail 'Tagged commit has not been merged into main.'
    printf 'Release tag %s verified on %s at %s.\n' "$TAG" "$MAIN_REF" "$TAG_COMMIT"
    ;;
  check|version|build|base|tag|name|channel)
    [[ $# -le 1 ]] || usage
    check
    case "$COMMAND" in
      check) printf 'Version metadata valid: %s / build %s.\n' "$VERSION" "$BUILD" ;;
      version) printf '%s\n' "$VERSION" ;;
      build) printf '%s\n' "$BUILD" ;;
      base) printf '%s\n' "$BASE" ;;
      tag) printf 'v%s\n' "$VERSION" ;;
      name) printf 'WeChat2AI v%s\n' "$VERSION" ;;
      channel) if [[ "$VERSION" == *-* ]]; then printf 'prerelease\n'; else printf 'stable\n'; fi ;;
    esac
    ;;
  *) usage ;;
esac
