#!/bin/zsh
# Packages build/TidyUpMyFiles.app (from build-app.sh) into the release files:
#   build/TidyUpMyFiles-$VERSION.dmg                 the app, with an Applications shortcut to drag onto
#   build/tidyup-$VERSION-macos-universal.tar.gz     the command line tool on its own
#   build/checksums.txt                              SHA-256 of both
# Optional, for a Developer ID build: SIGN_IDENTITY plus NOTARY_PROFILE (a profile saved with
# `xcrun notarytool store-credentials`) signs, notarizes and staples the DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:?Set VERSION, e.g. VERSION=1.2.0}"
APP="build/TidyUpMyFiles.app"
DMG="build/TidyUpMyFiles-$VERSION.dmg"
CLI_ARCHIVE="build/tidyup-$VERSION-macos-universal.tar.gz"
[[ -d "$APP" ]] || { echo "Missing $APP; run scripts/build-app.sh first." >&2; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir "$STAGING/dmg"
ditto "$APP" "$STAGING/dmg/TidyUpMyFiles.app"
ln -s /Applications "$STAGING/dmg/Applications"
rm -f "$DMG"
hdiutil create -volname "TidyUpMyFiles" -srcfolder "$STAGING/dmg" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    : "${SIGN_IDENTITY:?NOTARY_PROFILE needs SIGN_IDENTITY (a Developer ID Application identity)}"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

mkdir "$STAGING/cli"
cp build/tidyup LICENSE README.md "$STAGING/cli/"
tar -czf "$CLI_ARCHIVE" -C "$STAGING/cli" tidyup LICENSE README.md

(cd build && shasum -a 256 "${DMG:t}" "${CLI_ARCHIVE:t}" > checksums.txt)
echo "$DMG"
echo "$CLI_ARCHIVE"
echo "build/checksums.txt"
