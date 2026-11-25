---
name: release-check
description: Check TidyUpMyFiles is ready to publish or release — build, tests, safety promises, docs, changelog and repository hygiene. Use before tagging a release or when asked "is it ready?".
---

# Release check

Report each item as passed or failed, in plain words.

1. **Build and test**
   - `swift build` finishes with no warnings.
   - `swift test` passes.
   - `./scripts/build-app.sh` builds `build/TidyUpMyFiles.app` with `tidyup` inside it, and
     `codesign --verify --deep build/TidyUpMyFiles.app` succeeds.
2. **Safety promises** (read the code paths that changed since the last release):
   nothing deletes permanently, every new action stores undo data, `SafetyGuard` still refuses system
   folders, `~/Library`, `.git` and apps, and new rules start in preview mode.
3. **MCP server:** `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | build/tidyup mcp`
   lists the tools.
4. **Docs:** README links and images resolve (`.github/assets/` only), `docs/` pages match the behaviour,
   and `CHANGELOG.md` has an entry under a new version heading with today's date.
5. **Dependencies:** versions in `Package.swift` are exact, `Package.resolved` is committed, and the
   Dependabot cooldown is still 7 days.
6. **Repository:** `git status` is clean, and nothing ignored by `.gitignore` is tracked
   (`git ls-files -ci --exclude-standard` prints nothing).

To ship outside your own Mac, sign and notarize as described in README.md (Build from source).
