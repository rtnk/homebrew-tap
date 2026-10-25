#!/bin/bash
# Tests of update-formula.sh on fake Releases (file:// assets, no network): a correct bump, the formula's own version,
# an older version, a draft, a pre-release, a bad tag, a requested version that differs, a missing asset, and the three
# checksum sources disagreeing. Each case runs on a copy of Formula/tapcue.rb.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/.github/scripts/update-formula.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

current="$(sed -nE 's|^  url ".*/tapcue-([0-9.]+)-macos-arm64\.zip"$|\1|p' "$root/Formula/tapcue.rb")"
current_sha="$(sed -nE 's|^  sha256 "([0-9a-f]{64})"$|\1|p' "$root/Formula/tapcue.rb")"
next="$(echo "$current" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 + 1 }')"
older="0.0.1"

# A fake archive for version $1 in $work/assets/$1; prints its sha256.
make_assets() {
  local dir="$work/assets/$1"
  mkdir -p "$dir"
  printf 'tapcue %s\n' "$1" > "$dir/tapcue-$1-macos-arm64.zip"
  (cd "$dir" && sha256sum "tapcue-$1-macos-arm64.zip" > SHA256SUMS)
  cut -d' ' -f1 "$dir/SHA256SUMS"
}

# release <tag> <version> <draft> <prerelease> <digest> > release.json
release() {
  local dir="$work/assets/$2"
  jq -n --arg tag "$1" --argjson draft "$3" --argjson pre "$4" --arg digest "$5" \
    --arg zip "tapcue-$2-macos-arm64.zip" --arg zip_url "file://$dir/tapcue-$2-macos-arm64.zip" \
    --arg sums_url "file://$dir/SHA256SUMS" '{
      tag_name: $tag, draft: $draft, prerelease: $pre,
      assets: [
        { name: $zip, browser_download_url: $zip_url, digest: $digest },
        { name: "SHA256SUMS", browser_download_url: $sums_url, digest: "sha256:0" }
      ]
    }'
}

passed=0
# expect <name> <ok|fail> <expected action or error text> <release.json> [VERSION]
expect() {
  local name="$1" want="$2" match="$3" json="$4" version="${5:-}"
  local formula="$work/$name.rb" output="$work/$name.out" log="$work/$name.log" status=0
  cp "$root/Formula/tapcue.rb" "$formula"
  : > "$output"
  RELEASE_JSON="$json" FORMULA_FILE="$formula" GITHUB_OUTPUT="$output" VERSION="$version" \
    "$script" > "$log" 2>&1 || status=$?
  if [ "$want" = ok ] && [ "$status" -eq 0 ] && grep -qx "action=$match" "$output"; then
    :
  elif [ "$want" = fail ] && [ "$status" -ne 0 ] && grep -qF "$match" "$log" && ! grep -q "action=update" "$output"; then
    cmp -s "$formula" "$root/Formula/tapcue.rb" || { echo "FAIL $name: the formula was changed"; exit 1; }
  else
    echo "FAIL $name (status $status)"
    sed 's/^/  | /' "$log" "$output"
    exit 1
  fi
  echo "ok   $name"
  passed=$((passed + 1))
}

next_sha="$(make_assets "$next")"
make_assets "$older" > /dev/null
make_assets "$current" > /dev/null

release "v$next" "$next" false false "sha256:$next_sha" > "$work/bump.json"
expect bump ok update "$work/bump.json"
formula="$work/bump.rb"
grep -qx "  url \"https://github.com/rtnk/TapCue/releases/download/v$next/tapcue-$next-macos-arm64.zip\"" "$formula"
grep -qx "  sha256 \"$next_sha\"" "$formula"
grep -qx "version=$next" "$work/bump.out"
grep -qx "branch=bump/tapcue-$next" "$work/bump.out"
test "$(diff "$root/Formula/tapcue.rb" "$formula" | grep -c '^[<>]')" -eq 4 # url and sha256 only
echo "ok   bump rewrites url and sha256 only"

expect bump-requested ok update "$work/bump.json" "$next"
release "v$current" "$current" false false "sha256:$current_sha" > "$work/same.json"
expect up-to-date ok skip "$work/same.json"
release "v$older" "$older" false false "sha256:x" > "$work/older.json"
expect older fail "lower than the formula" "$work/older.json"
release "v$next" "$next" true false "sha256:$next_sha" > "$work/draft.json"
expect draft fail "draft Release" "$work/draft.json"
release "v$next" "$next" false true "sha256:$next_sha" > "$work/pre.json"
expect prerelease fail "pre-release" "$work/pre.json"
release "v$next-rc.1" "$next" false false "sha256:$next_sha" > "$work/rc.json"
expect bad-tag fail "is not vMAJOR.MINOR.PATCH" "$work/rc.json"
expect other-version fail "asked for 9.9.9" "$work/bump.json" 9.9.9
expect bad-input fail "is not MAJOR.MINOR.PATCH" "$work/bump.json" "1.2"
release "v$next" "$next" false false "sha256:$(printf '0%.0s' {1..64})" > "$work/digest.json"
expect wrong-digest fail "GitHub's digest" "$work/digest.json"
jq 'del(.assets[1])' "$work/bump.json" > "$work/nosums.json"
expect no-sums fail "no asset SHA256SUMS" "$work/nosums.json"
cp -r "$work/assets/$next" "$work/assets/tampered"
echo "0000000000000000000000000000000000000000000000000000000000000000  tapcue-$next-macos-arm64.zip" \
  > "$work/assets/tampered/SHA256SUMS"
jq --arg u "file://$work/assets/tampered/SHA256SUMS" '.assets[1].browser_download_url = $u' "$work/bump.json" \
  > "$work/sums.json"
expect wrong-sums fail "does not list" "$work/sums.json"

echo "$passed cases passed"
