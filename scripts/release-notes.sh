#!/bin/bash
# Writes Markdown release notes for TAG (e.g. v1.3.0) from the commits since the previous v* tag.
#   scripts/release-notes.sh v1.3.0 > notes.md
# docs, test, chore, ci, style and build commits are left out; merge commits too.
set -euo pipefail

TAG="${1:?Usage: release-notes.sh <tag>}"
VERSION="${TAG#v}"
REPO="${GITHUB_REPOSITORY:-k0wl0n/TidyUpMyFiles}"
LAST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
RANGE="${LAST_TAG:+$LAST_TAG..}HEAD"
LOG="$(git log --no-merges --format='%s (%h)' "$RANGE")"
BREAKING="$(git log --no-merges --format='%H' "$RANGE" | while read -r sha; do
    message="$(git log -1 --format=%B "$sha")"
    if grep -Eq '^[a-z]+(\([^)]*\))?!:' <<<"$message" || grep -Eq '^BREAKING[ -]CHANGE:' <<<"$message"; then
        git log -1 --format='%s (%h)' "$sha"
    fi
done)"

section() { # section <title> <subject regex>
    local lines
    lines="$(grep -E "$2" <<<"$LOG" | sed -E 's/^[a-z]+(\([^)]*\))?!?: //; s/^/- /' || true)"
    [[ -n "$lines" ]] && printf '### %s\n\n%s\n\n' "$1" "$lines"
    return 0
}

{
    [[ -n "$BREAKING" ]] && printf '### Breaking changes\n\n%s\n\n' "$(sed 's/^/- /' <<<"$BREAKING")"
    section "Features" '^feat(\([^)]*\))?!?:'
    section "Fixes" '^fix(\([^)]*\))?!?:'
    section "Performance" '^perf(\([^)]*\))?!?:'
    section "Other changes" '^refactor(\([^)]*\))?!?:'
    cat <<EOF
### Install

1. Download **TidyUpMyFiles-$VERSION.dmg** below, open it and drag the app to **Applications**.
2. The app isn't notarized by Apple yet, so the first time you open it macOS says it "could not verify" it.
   Click **Done**, then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   Or run: \`xattr -dr com.apple.quarantine /Applications/TidyUpMyFiles.app\`

Homebrew: \`brew install --cask k0wl0n/tap/tidyupmyfiles\` (app) or \`brew install k0wl0n/tap/tidyup\` (command line only).

Verify the download:

\`\`\`sh
shasum -a 256 -c checksums.txt
gh attestation verify TidyUpMyFiles-$VERSION.dmg --repo $REPO
\`\`\`
EOF
}
