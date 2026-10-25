# rtnk/homebrew-tap

Homebrew tap for [TapCue](https://github.com/rtnk/TapCue), a local command-line tool and MCP server for mobile UI
tests on iOS Simulators and Android emulators. TapCue is based on [Maestro](https://github.com/mobile-dev-inc/Maestro)
(Apache-2.0) and is not affiliated with mobile.dev.

The `tapcue` formula installs the archive published in the
[TapCue GitHub Releases](https://github.com/rtnk/TapCue/releases) as is: nothing is built on your Mac, and the download
is checked against the SHA-256 in [`Formula/tapcue.rb`](Formula/tapcue.rb).

## Installation

```sh
brew install rtnk/tap/tapcue
```

This taps `rtnk/tap` and installs `tapcue` together with its Java runtime (`openjdk@21` from Homebrew).

## Verify

```sh
tapcue --version
```

The first line is `tapcue <version>`, e.g. `tapcue 0.1.0`. `tapcue --help` lists the commands.

## Update

```sh
brew update
brew upgrade tapcue
```

## Uninstall

```sh
brew uninstall tapcue
brew untap rtnk/tap        # optional
rm -rf ~/.tapcue           # optional: TapCue's state, logs and the iOS driver it built
```

`brew uninstall` also removes `openjdk@21` when no other formula needs it.

## Requirements

| | |
|---|---|
| **macOS** | macOS 15 Sequoia or newer on **Apple silicon** (arm64). The release archive is built for Apple silicon only; on an Intel Mac `brew install` stops with an architecture error. |
| **Java** | Java 17 or newer. The formula installs `openjdk@21` and `tapcue` uses it unless `JAVA_HOME` is set (see [Troubleshooting](#java_home-points-to-another-java)). |
| **Android** | The Android SDK platform tools (`adb`) and an emulator or a device. Commands that manage emulators (`tapcue start-device`) also need `ANDROID_HOME` (or `ANDROID_SDK_ROOT`) pointing at the SDK. |
| **iOS Simulator** | Xcode with its command-line tools. TapCue ships no prebuilt iOS driver: on the first iOS run it builds the XCTest runner from source with your Xcode (a few minutes, no network needed) and keeps it in `~/.tapcue`. `tapcue driver-setup --simulator` builds it ahead of time. |
| **Maestro** | Not needed. TapCue does not use a Maestro installation or `~/.maestro`. |

## Troubleshooting

### `JAVA_HOME` points to another Java

`tapcue` uses `$JAVA_HOME` when it is set and Homebrew's `openjdk@21` otherwise. Any Java 17 or newer works. To use
Homebrew's Java for one run, or to check whether your `JAVA_HOME` is the problem:

```sh
echo "$JAVA_HOME"
JAVA_HOME= tapcue --version
```

To always use Homebrew's Java, remove the `JAVA_HOME` export from your shell profile or point it at
`$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home`.

### "ERROR: Java 17 or higher is required."

`JAVA_HOME` (or, without it, the `java` on your `PATH`) is older than Java 17. Check it with
`"$JAVA_HOME/bin/java" -version`, then unset `JAVA_HOME` or point it at Java 17+ as above. If `openjdk@21` is
missing or broken, reinstall it: `brew reinstall openjdk@21`.

### Android: no device, `adb` not found, "Ensure that either ANDROID_HOME or ANDROID_SDK_ROOT is set"

Install the Android SDK platform tools (with Android Studio, or `brew install --cask android-platform-tools`), make
sure `adb devices` lists your emulator or device, and for emulator management export the SDK location:

```sh
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
```

### iOS: Xcode or the simulator driver is missing

`xcode-select -p` must point at a full Xcode (not only the Command Line Tools), and the Xcode license must be
accepted:

```sh
xcode-select -p                                   # e.g. /Applications/Xcode.app/Contents/Developer
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
tapcue driver-setup --simulator                   # builds the driver; the log is in ~/.tapcue/
```

### Maestro is installed too

There is no conflict: Maestro installs `maestro`, TapCue installs `tapcue`, and their state lives in `~/.maestro` and
`~/.tapcue` respectively. Both can be installed at the same time. A project's `.maestro/` directory is not read by
TapCue; rename it to `.tapcue/`.

### "SHA256 mismatch" / "Formula reports different checksum"

The downloaded archive does not match the formula. Clear the cached download and try again:

```sh
rm -f "$(brew --cache --formula rtnk/tap/tapcue)"
brew update
brew install rtnk/tap/tapcue
```

If it still fails, the download is being altered on the way (a proxy or captive portal) or the Release and the formula
disagree. Compare with the `SHA256SUMS` file of the
[Release](https://github.com/rtnk/TapCue/releases) and [open an issue](https://github.com/rtnk/homebrew-tap/issues);
do not edit the checksum by hand.

### The GitHub Release cannot be downloaded

The archive comes from `https://github.com/rtnk/TapCue/releases/download/…` and needs no GitHub account. Check that
`github.com` and the host it redirects downloads to (`objects.githubusercontent.com`) are reachable:

```sh
curl -fsSLI "$(brew info --json=v2 rtnk/tap/tapcue | jq -r '.formulae[0].urls.stable.url')"
```

Behind a proxy, set `HTTPS_PROXY` for `brew`. A `404` means the formula points at a Release that does not exist;
please [open an issue](https://github.com/rtnk/homebrew-tap/issues).

## For maintainers

### Publishing a new TapCue version in Homebrew

1. Release TapCue as described in
   [`docs/RELEASING.md`](https://github.com/rtnk/TapCue/blob/main/docs/RELEASING.md): the annotated tag `vX.Y.Z`
   publishes `tapcue-X.Y.Z-macos-arm64.zip` and `SHA256SUMS`. Only stable Releases (not drafts or pre-releases) go into
   the formula, and never a version lower than the current one.
2. Take the checksum from the Release and check it against the downloaded archive:

   ```sh
   V=X.Y.Z
   curl -fsSLO "https://github.com/rtnk/TapCue/releases/download/v$V/SHA256SUMS"
   curl -fsSLO "https://github.com/rtnk/TapCue/releases/download/v$V/tapcue-$V-macos-arm64.zip"
   shasum -a 256 -c SHA256SUMS
   ```

3. On a new branch, change `url` and `sha256` in [`Formula/tapcue.rb`](Formula/tapcue.rb) (the version comes from
   the URL), then open a pull request to `main`. Changes to `main` go only through pull requests.
4. CI must be green before merging:
   - **Validate** runs `ruby -c`, `brew style` and `brew audit --strict --online`. On macOS 15 and 26 it checks
     integrity (formula == `SHA256SUMS` == download) and that a wrong checksum is rejected, then upgrades from the
     formula on `main`, installs, runs `brew test`, checks PATH, `--version`, `--help` and Java, and uninstalls. It also
     checks that installation is refused on Intel.
   - **Smoke** runs `check-syntax`, the MCP server, the iOS Simulator driver build and a simulator UI hierarchy with the
     formula's Java.
5. After merging, users get the version with `brew update && brew upgrade tapcue`.

**Public install** runs the commands above against the tap on github.com every Monday and on demand
(Actions → Public install → Run workflow), so a broken Release or dependency shows up without a change in the tap.

Locally, the same checks are:

```sh
brew tap rtnk/tap "$PWD"   # or work in "$(brew --repository rtnk/tap)"
brew style --formula rtnk/tap/tapcue
brew audit --strict --online --formula rtnk/tap/tapcue
brew install --formula rtnk/tap/tapcue && brew test rtnk/tap/tapcue
```

### Changing the Java version

The formula depends on `openjdk@21` (`depends_on` and `Language::Java.overridable_java_home_env("21")`). Change both
together, and let **Smoke** pass before merging. Homebrew deprecates `openjdk@21` on 2028-09-30.

## License

[Apache License 2.0](LICENSE). TapCue itself is licensed under Apache-2.0; see its
[`LICENSE`](https://github.com/rtnk/TapCue/blob/main/LICENSE) and
[`NOTICE`](https://github.com/rtnk/TapCue/blob/main/NOTICE).
