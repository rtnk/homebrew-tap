#!/bin/bash
# Makes the checkout the tap rtnk/tap, the way Homebrew/actions/setup-homebrew links a tap under test.
set -euo pipefail
taps="$(brew --repository)/Library/Taps/rtnk"
mkdir -p "$taps"
rm -rf "$taps/homebrew-tap"
ln -s "${GITHUB_WORKSPACE:-$PWD}" "$taps/homebrew-tap"
brew tap | grep -qx rtnk/tap
echo "rtnk/tap -> $(readlink "$taps/homebrew-tap")"
