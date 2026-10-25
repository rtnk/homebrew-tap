#!/bin/bash
# Points Formula/tapcue.rb at a TapCue GitHub Release (used by .github/workflows/update-formula.yml).
#
#   VERSION=X.Y.Z .github/scripts/update-formula.sh     # that Release
#   .github/scripts/update-formula.sh                   # the latest stable Release
#
# Refuses drafts, pre-releases, tags other than vMAJOR.MINOR.PATCH and versions lower than the formula's; the formula's
# own version is "up to date" (action=skip). Otherwise it downloads the archive and SHA256SUMS and requires the same
# SHA-256 from the download, from SHA256SUMS and from the asset digest GitHub reports, then rewrites url and sha256
# (action=update). Writes action, version, sha256 and branch to $GITHUB_OUTPUT.
#
# Environment: VERSION (optional), GH_TOKEN (optional, for API rate limits), FORMULA_FILE (default Formula/tapcue.rb),
# TAPCUE_REPO (default rtnk/TapCue), RELEASE_JSON (a file used instead of the API, for tests).
set -euo pipefail

repo="${TAPCUE_REPO:-rtnk/TapCue}"
formula="${FORMULA_FILE:-Formula/tapcue.rb}"
requested="${VERSION:-}"
out="${GITHUB_OUTPUT:-/dev/null}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "::error::$*" >&2
  exit 1
}

semver='^[0-9]+\.[0-9]+\.[0-9]+$'
if [ -n "$requested" ] && [[ ! "$requested" =~ $semver ]]; then
  fail "version '$requested' is not MAJOR.MINOR.PATCH"
fi

api() {
  local auth=()
  if [ -n "${GH_TOKEN:-}" ]; then auth=(-H "Authorization: Bearer $GH_TOKEN"); fi
  curl -fsSL --retry 3 "${auth[@]}" -H "Accept: application/vnd.github+json" "https://api.github.com/$1"
}

if [ -n "${RELEASE_JSON:-}" ]; then
  cp "$RELEASE_JSON" "$work/release.json"
elif [ -n "$requested" ]; then
  api "repos/$repo/releases/tags/v$requested" > "$work/release.json" || fail "no published Release v$requested in $repo"
else
  # /releases/latest never returns drafts or pre-releases.
  api "repos/$repo/releases/latest" > "$work/release.json" || fail "no latest Release in $repo"
fi

tag="$(jq -r '.tag_name' "$work/release.json")"
[ "$(jq -r '.draft' "$work/release.json")" = false ] || fail "$tag is a draft Release"
[ "$(jq -r '.prerelease' "$work/release.json")" = false ] || fail "$tag is a pre-release; the formula takes stable Releases only"
[[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || fail "tag '$tag' is not vMAJOR.MINOR.PATCH"
version="${BASH_REMATCH[1]}"
if [ -n "$requested" ] && [ "$version" != "$requested" ]; then
  fail "asked for $requested, the Release is $tag"
fi

current="$(sed -nE 's|^  url "https://.*/tapcue-([0-9]+\.[0-9]+\.[0-9]+)-macos-arm64\.zip"$|\1|p' "$formula")"
[ -n "$current" ] || fail "no tapcue-<version>-macos-arm64.zip url in $formula"
echo "formula: $current, Release: $version"
if [ "$version" = "$current" ]; then
  echo "::notice::$formula is up to date ($current)."
  echo "action=skip" >> "$out"
  exit 0
fi
if [ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -n 1)" != "$version" ]; then
  fail "$version is lower than the formula's $current; the formula never goes back to an older version"
fi

zip="tapcue-$version-macos-arm64.zip"
asset() { jq -r --arg name "$1" --arg key "$2" '.assets[] | select(.name == $name) | .[$key] // empty' "$work/release.json"; }
zip_url="$(asset "$zip" browser_download_url)"
sums_url="$(asset SHA256SUMS browser_download_url)"
digest="$(asset "$zip" digest)"
[ -n "$zip_url" ] || fail "$tag has no asset $zip"
[ -n "$sums_url" ] || fail "$tag has no asset SHA256SUMS"
[ -n "$digest" ] || fail "GitHub reports no digest for $zip"

curl -fsSL --retry 3 -o "$work/$zip" "$zip_url"
curl -fsSL --retry 3 -o "$work/SHA256SUMS" "$sums_url"
if command -v sha256sum > /dev/null; then
  sha="$(sha256sum "$work/$zip" | cut -d' ' -f1)"
else
  sha="$(shasum -a 256 "$work/$zip" | cut -d' ' -f1)"
fi
echo "sha256 of the download: $sha"
grep -qx "$sha  $zip" "$work/SHA256SUMS" || fail "SHA256SUMS of $tag does not list $sha for $zip"
[ "$digest" = "sha256:$sha" ] || fail "GitHub's digest for $zip is $digest, the download is sha256:$sha"

url="https://github.com/$repo/releases/download/$tag/$zip"
sed -i.bak -E \
  -e "s|^  url \"https://.*/tapcue-[0-9.]+-macos-arm64\\.zip\"$|  url \"$url\"|" \
  -e "s|^  sha256 \"[0-9a-f]{64}\"$|  sha256 \"$sha\"|" \
  "$formula"
rm -f "$formula.bak"
grep -qx "  url \"$url\"" "$formula" || fail "url not updated in $formula"
grep -qx "  sha256 \"$sha\"" "$formula" || fail "sha256 not updated in $formula"
echo "$formula: $current -> $version"

{
  echo "action=update"
  echo "version=$version"
  echo "sha256=$sha"
  echo "branch=bump/tapcue-$version"
} >> "$out"
