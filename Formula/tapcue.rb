class Tapcue < Formula
  desc "Local mobile UI test automation command-line tool and MCP server"
  homepage "https://github.com/rtnk/TapCue"
  url "https://github.com/rtnk/TapCue/releases/download/v0.1.0/tapcue-0.1.0-macos-arm64.zip"
  sha256 "e8dd01b061f5fe9d381cf510c65161c7181108833e0c05c757796750ddab6ec1"
  license "Apache-2.0"

  livecheck do
    url :stable
    strategy :github_latest
  end

  # The release archive is built for Apple silicon only (no macOS x64 Skia runtime); OpenJDK bottles start at Sequoia.
  depends_on arch: :arm64
  depends_on macos: :sequoia
  depends_on "openjdk@21"

  def install
    # bin/tapcue resolves lib/ relative to itself, so the archive stays together in libexec.
    libexec.install Dir["*"]
    (bin/"tapcue").write_env_script libexec/"bin/tapcue", Language::Java.overridable_java_home_env("21")
  end

  test do
    assert_match "tapcue #{version}", shell_output("#{bin}/tapcue --version")
    assert_match "Usage:", shell_output("#{bin}/tapcue --help")

    (testpath/"flow.yaml").write <<~YAML
      appId: com.example
      ---
      - launchApp
    YAML
    system bin/"tapcue", "check-syntax", testpath/"flow.yaml"
  end
end
