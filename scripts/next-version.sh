#!/bin/bash
# Prints the next release tag (e.g. v1.3.0) from the Conventional Commits since the last v* tag,
# or prints nothing when those commits don't call for a release.
#   scripts/next-version.sh [auto|patch|minor|major]      (default: auto)
# auto: feat! / "BREAKING CHANGE:" → major (minor while still 0.x), feat → minor, fix / perf → patch;
# docs, chore, test, ci, style, refactor and build alone → no release.
set -euo pipefail

BUMP="${1:-auto}"
case "$BUMP" in auto|patch|minor|major) ;; *) echo "Unknown bump '$BUMP' (auto|patch|minor|major)" >&2; exit 2 ;; esac

LAST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
if [[ -n "$LAST_TAG" ]]; then
    RANGE="$LAST_TAG..HEAD"
    CURRENT="${LAST_TAG#v}"
else
    RANGE="HEAD"
    CURRENT="0.0.0"
fi

if [[ -z "$(git rev-list --no-merges "$RANGE")" ]]; then
    echo "No new commits since ${LAST_TAG:-the start}; nothing to release." >&2
    exit 0
fi

if [[ "$BUMP" == "auto" ]]; then
    SUBJECTS="$(git log --no-merges --format=%s "$RANGE")"
    MESSAGES="$(git log --no-merges --format=%B "$RANGE")"
    SCOPE='(\([^)]*\))?'
    if grep -Eq "^[a-z]+$SCOPE!:" <<<"$SUBJECTS" || grep -Eq '^BREAKING[ -]CHANGE:' <<<"$MESSAGES"; then
        BUMP="major"
    elif grep -Eq "^feat$SCOPE:" <<<"$SUBJECTS"; then
        BUMP="minor"
    elif grep -Eq "^(fix|perf)$SCOPE:" <<<"$SUBJECTS"; then
        BUMP="patch"
    else
        echo "Only docs/chore/test/ci-style commits since ${LAST_TAG:-the start}; nothing to release." >&2
        exit 0
    fi
fi

IFS=. read -r MAJOR MINOR PATCH <<<"$CURRENT"
PATCH="${PATCH%%[!0-9]*}"
# Before 1.0, breaking changes are expected; they move the minor number instead of jumping to 1.0.
if [[ "$BUMP" == "major" && "$MAJOR" == "0" && "${1:-auto}" == "auto" ]]; then
    BUMP="minor"
fi
case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
esac
echo "v$MAJOR.$MINOR.$PATCH"
