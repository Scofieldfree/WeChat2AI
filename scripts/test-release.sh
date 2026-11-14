#!/bin/bash
# Exercise release boundaries only in an owned temporary repository.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wechat2ai-release-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/Resources"
cp "$REPO/scripts/version.sh" "$TEST_ROOT/scripts/"
cp "$REPO/Resources/App-Info.plist" "$REPO/Resources/Share-Info.plist" "$TEST_ROOT/Resources/"
cd "$TEST_ROOT"
printf '{"version":"0.1.0","build":1}\n' > version.json
for plist in Resources/*.plist; do
  /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.0' "$plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' "$plist"
done
COUNT=0
pass() { COUNT=$((COUNT + 1)); printf 'PASS %s\n' "$1"; }
ok() {
  local title=$1; shift
  if ! "$@" > result.txt 2>&1; then cat result.txt >&2; printf 'FAIL %s\n' "$title" >&2; exit 1; fi
  pass "$title"
}
reject() {
  local title=$1; shift
  if "$@" > result.txt 2>&1; then printf 'FAIL unexpectedly accepted: %s\n' "$title" >&2; exit 1; fi
  pass "$title"
}

ok 'Existing numeric version and build' bash scripts/version.sh check
ok 'Set preview and synchronize both bundles' bash scripts/version.sh set 0.1.1-beta.1 2
[[ $(bash scripts/version.sh tag) == v0.1.1-beta.1 && $(bash scripts/version.sh name) == 'WeChat2AI v0.1.1-beta.1' && $(bash scripts/version.sh channel) == prerelease && $(bash scripts/version.sh base) == 0.1.1 ]]
pass 'Preview tag, title, channel and Apple numeric version agree'
for invalid in 01.2.3 0.2 v0.1.1 0.1.1-preview.1 0.1.1-beta.0 0.1.1-beta.01 0.1.1+local; do
  reject "Reject invalid version $invalid" bash scripts/version.sh set "$invalid" 3
done
reject 'Reject unchanged build for a changed version' bash scripts/version.sh set 0.1.1 2
reject 'Reject decreasing build' bash scripts/version.sh set 0.1.1 1
reject 'Reject zero build' bash scripts/version.sh set 0.1.1 0
reject 'Reject leading zero build' bash scripts/version.sh set 0.1.1 03
ok 'Promote release with a new build' bash scripts/version.sh set 0.1.1 3
[[ $(bash scripts/version.sh channel) == stable ]]; pass 'Numeric target identifies stable channel'
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 4' Resources/Share-Info.plist
reject 'Reject extension version drift' bash scripts/version.sh check
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 3' Resources/Share-Info.plist
plutil -replace CFBundleVersion -integer 3 Resources/App-Info.plist
reject 'Reject Apple build encoded as an integer' bash scripts/version.sh check
plutil -replace CFBundleVersion -string 3 Resources/App-Info.plist
plutil -replace build -string 3 version.json
reject 'Reject JSON build encoded as a string' bash scripts/version.sh check
plutil -replace build -integer 3 version.json

git init --quiet --initial-branch=main --template=
git config user.name 'Release test'
git config user.email 'release-test@example.invalid'
git config commit.gpgsign false
git config tag.gpgSign false
git config core.hooksPath /dev/null
# Only source identity belongs in this temporary repository, not test output.
git add version.json Resources scripts
git commit --quiet -m 'Synthetic release baseline'
git tag -a v0.1.1 -m 'Synthetic release tag'
ok 'Accept annotated tag on main' bash scripts/version.sh check-tag v0.1.1 main
reject 'Reject tag differing from canonical version' bash scripts/version.sh check-tag v9.9.9 main
reject 'Reject missing remote main' bash scripts/version.sh check-tag v0.1.1
reject 'Reject arbitrary release source branch' bash scripts/version.sh check-tag v0.1.1 feature
git checkout --quiet -b feature
printf 'Synthetic unmerged change.\n' > feature.txt
git add feature.txt; git commit --quiet -m 'Synthetic feature-only commit'
git tag -d v0.1.1 >/dev/null; git tag -a v0.1.1 -m 'Synthetic unmerged tag'
reject 'Reject matching annotated tag outside main' bash scripts/version.sh check-tag v0.1.1 main
git checkout --quiet main
git tag -d v0.1.1 >/dev/null; git tag -a v0.1.1 -m 'Synthetic main tag'
printf 'Synthetic later main commit.\n' > later.txt
git add later.txt; git commit --quiet -m 'Synthetic later commit'
reject 'Reject checkout different from tagged commit' bash scripts/version.sh check-tag v0.1.1 main
git checkout --quiet --detach v0.1.1
ok 'Accept detached tag from main history' bash scripts/version.sh check-tag v0.1.1 main
git update-ref refs/remotes/origin/main main
ok 'Accept remote main in a detached CI checkout' bash scripts/version.sh check-tag v0.1.1
printf '\n' >> Resources/App-Info.plist
reject 'Reject modified tracked release source' bash scripts/version.sh check-tag v0.1.1 main
git checkout -- Resources/App-Info.plist
git tag -d v0.1.1 >/dev/null; git tag v0.1.1
reject 'Reject lightweight tag' bash scripts/version.sh check-tag v0.1.1 main
printf '%s release rule checks; 0 failures\n' "$COUNT"
