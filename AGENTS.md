# Instructions for coding agents

TidyUpMyFiles is a free, open-source (MIT) macOS menu bar app that tidies folders with rules. It is a
Swift package; read [README.md](README.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first.

## Layout

- `Sources/TidyUpMyFilesCore/` — engine and services, no UI (rules, YAML, matching, actions, undo,
  watcher, Smart Trash, AI, MCP server). Put logic here so it can be tested.
- `Sources/TidyUpMyFilesApp/` — SwiftUI menu bar app and main window (`AppModel` holds the state).
- `Sources/TidyUpMyFilesCLI/` — the `tidyup` command, including `tidyup mcp`.
- `Tests/TidyUpMyFilesCoreTests/` — XCTest; `SandboxTestCase` gives a temporary folder and a fake Trash.
- `docs/` — user guide, rules, CLI, MCP and architecture references.
- `.claude/skills/` — step-by-step skills for common jobs in this repo.

## Commands

```sh
swift build                 # must finish with no warnings (strict concurrency is on)
swift test                  # all tests must pass
./scripts/build-app.sh      # universal TidyUpMyFiles.app (with tidyup inside) in ./build
```

Try things in demo mode only: `TIDYUP_DEMO_HOME=/tmp/some-folder` keeps `~`, the Trash, settings and
logs inside that folder. Never run `tidyup run` or the app against the real home folder while testing.

## Rules that must never break

- **Never delete files permanently.** Removal means the Trash. Overwriting needs `allow_overwrite` on the
  rule, and the replaced file goes to the Trash.
- **Everything is undoable.** New actions must store undo data and be covered by `UndoService`.
- **Off-limits places** (`SafetyGuard`): system folders, `~/Library`, `.git` folders and app bundles.
  A folder is never moved into itself.
- **Preview first.** New rules start in preview mode; scanning and `simulate` change nothing.
- **Opt-in power.** Shell scripts and Shortcuts stay off unless the person turns them on.
- **Private AI.** Only allowed folders, names and metadata by default, suggestions wait for approval,
  keys live in the Keychain.
- **Tests touch temporary folders only.**

## Conventions

- Clean-room project: never decompile, unpack or copy code, text, icons or assets from other apps.
- Dependencies are pinned exactly (`Package.resolved`, Yams 6.2.2). Avoid new ones; if one is truly
  needed, pin an exact version and keep the 7-day release-age rule (Dependabot cooldown).
- Follow the existing code style; comment only what isn't obvious.
- Conventional Commits, lowercase and imperative: `fix(preview): keep the folded state after a rescan`.
  Don't rewrite history or push unless asked.
- Only commit files that belong in the public repo; respect `.gitignore` and never force-add ignored files.
- When behaviour changes, update README.md, the matching page in `docs/` and CHANGELOG.md.
- The person this project is built for doesn't code: explain results in short, plain sentences.
