#!/bin/bash
# Writes the Homebrew formula (tidyup command) and cask (app) for a release into OUT_DIR,
# using the checksums in build/checksums.txt from scripts/make-dmg.sh.
#   scripts/render-homebrew.sh 1.3.0 k0wl0n/TidyUpMyFiles path/to/homebrew-tap
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: render-homebrew.sh <version> <owner/repo> <out-dir>}"
REPO="${2:?Usage: render-homebrew.sh <version> <owner/repo> <out-dir>}"
OUT_DIR="${3:?Usage: render-homebrew.sh <version> <owner/repo> <out-dir>}"
DOWNLOADS="https://github.com/$REPO/releases/download/v$VERSION"

checksum_of() { awk -v name="$1" '$2 == name { print $1 }' build/checksums.txt; }
DMG_SHA="$(checksum_of "TidyUpMyFiles-$VERSION.dmg")"
CLI_SHA="$(checksum_of "tidyup-$VERSION-macos-universal.tar.gz")"
[[ -n "$DMG_SHA" && -n "$CLI_SHA" ]] || { echo "build/checksums.txt has no entries for $VERSION" >&2; exit 1; }

mkdir -p "$OUT_DIR/Formula" "$OUT_DIR/Casks"

cat > "$OUT_DIR/Formula/tidyup.rb" <<EOF
class Tidyup < Formula
  desc "Command-line tool and MCP server for TidyUpMyFiles folder rules"
  homepage "https://github.com/$REPO"
  url "$DOWNLOADS/tidyup-$VERSION-macos-universal.tar.gz"
  sha256 "$CLI_SHA"
  version "$VERSION"
  license "MIT"

  depends_on :macos

  def install
    bin.install "tidyup"
  end

  test do
    # Usage text exits with 64 (EX_USAGE).
    assert_match "tidyup sim", shell_output("#{bin}/tidyup --help", 64)
  end
end
EOF

cat > "$OUT_DIR/Casks/tidyupmyfiles.rb" <<EOF
cask "tidyupmyfiles" do
  version "$VERSION"
  sha256 "$DMG_SHA"

  url "$DOWNLOADS/TidyUpMyFiles-#{version}.dmg"
  name "TidyUpMyFiles"
  desc "Menu bar app that tidies folders with rules, with preview and undo"
  homepage "https://github.com/$REPO"

  depends_on macos: :ventura

  app "TidyUpMyFiles.app"

  zap trash: [
    "~/Library/Application Support/TidyUpMyFiles",
    "~/Library/Logs/TidyUpMyFiles",
    "~/Library/Preferences/io.github.tidyupmyfiles.TidyUpMyFiles.plist",
  ]

  caveats <<~EOS
    TidyUpMyFiles is not notarized by Apple yet. The first time you open it, macOS says it
    "could not verify" the app: click Done, then go to System Settings → Privacy & Security
    and click Open Anyway.
  EOS
end
EOF
echo "$OUT_DIR/Formula/tidyup.rb"
echo "$OUT_DIR/Casks/tidyupmyfiles.rb"
