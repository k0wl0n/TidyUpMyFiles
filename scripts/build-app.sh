#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) TidyUpMyFiles.app and the tidyup CLI into ./build.
# Optional environment:
#   VERSION=1.2.0 BUILD_NUMBER=42   written into the built app's Info.plist (Resources/Info.plist is untouched)
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"   for a distributable, notarizable build
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64 --only-use-versions-from-resolved-file
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="build/TidyUpMyFiles.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BIN/TidyUpMyFilesApp" "$APP/Contents/MacOS/TidyUpMyFilesApp"
cp -f Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
"$BIN/TidyUpMyFilesApp" --export-icon build/AppIcon.iconset
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" build/AppIcon.iconset
cp -f "$BIN/tidyup" build/tidyup
# Inside the app too, so AI agents can start `tidyup mcp` from /Applications/TidyUpMyFiles.app.
cp -f "$BIN/tidyup" "$APP/Contents/MacOS/tidyup"

IDENTITY="${SIGN_IDENTITY:--}"
# Notarization needs a secure timestamp; ad hoc signatures can't have one.
if [[ "$IDENTITY" == "-" ]]; then TIMESTAMP="--timestamp=none"; else TIMESTAMP="--timestamp"; fi
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" build/tidyup
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP/Contents/MacOS/tidyup"
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP"
echo "Built $APP and build/tidyup (signed with: $IDENTITY)"
