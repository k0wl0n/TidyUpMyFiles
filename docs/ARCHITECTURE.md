# Architecture

TidyUpMyFiles is a Swift package with three products and one test target.

```
Sources/TidyUpMyFilesCore/    engine and services, no UI
  Model/       rules, conditions, file kinds, YAML coding
  Engine/      file facts, rule matching, name tokens, path safety
  Execution/   actions, activity store and log files, undo, preview checks, the organizer
  Watch/       FSEvents watcher and the watch service
  Storage/     rules and settings files, ready-made rules
  Trash/       Smart Trash
  AI/          optional suggestion providers
  MCP/         Model Context Protocol server for AI agents (`tidyup mcp`)
Sources/TidyUpMyFilesApp/     SwiftUI menu bar app and main window
Sources/TidyUpMyFilesCLI/     the `tidyup` command
Tests/TidyUpMyFilesCoreTests/ unit and integration tests (temporary folders and a fake Trash only)
Resources/                    Info.plist for the app bundle
scripts/build-app.sh          builds the universal app bundle (with tidyup inside)
scripts/make-dmg.sh           packs the release DMG, command line archive and checksums
scripts/next-version.sh       next version from Conventional Commits (used by the release workflow)
scripts/release-notes.sh      release notes from Conventional Commits
scripts/render-homebrew.sh    Homebrew formula and cask for a release
.github/workflows/            ci.yml (tests) and release.yml (manual release)
```

## How a file is handled

1. **Watch.** The folder watcher hears about new or changed items. Unfinished downloads (`.crdownload`,
   `.download`, `.part`, `.tmp`) and files that are still growing are skipped until they have been
   unchanged for 2 seconds.
2. **Read facts.** Only the details a rule needs are read: name and size always; Spotlight data, photo
   dates, text contents and duplicate checks only when a condition asks for them.
3. **Match.** The rule engine checks the folder's rules top to bottom and plans the steps of the first
   match (more with `continue_matching`).
4. **Preview or act.** Preview rules queue the plan for approval, with predicted name clashes and new
   folders. Live rules run it through the action executor.
5. **Record.** Every step is written to an SQLite activity store with what's needed to undo it, and to a
   monthly text log in `~/Library/Logs/TidyUpMyFiles/`.

## Safety model

- **Never deletes.** Removal always means the Trash. Replacing a file needs `allow_overwrite` on the rule,
  and the replaced file goes to the Trash too.
- **Everything is undoable.** Moves, renames, tags, colors and Trash steps store their undo data; a whole
  run can be undone at once.
- **Off-limits places.** A safety guard refuses system folders (`/System`, `/Library`, `/usr`,
  `/Applications` and similar), `~/Library`, anything inside a `.git` folder and app bundles, whatever a
  rule or an AI suggestion says. A folder is never moved, copied or packed into itself.
- **Preview first.** New rules start in preview mode; scanning never moves anything.
- **Opt-in power.** Shell scripts and Shortcuts are off until turned on in Settings.
- **Private AI.** AI is off by default, only for allowed folders, sends names and metadata unless a
  folder is opted in for contents, and every suggestion waits for approval. API keys stay in the Keychain.

## Where things are stored

| What | Where |
| --- | --- |
| Rules | `~/Library/Application Support/TidyUpMyFiles/rules.yaml` |
| Settings (no secrets) | `~/Library/Application Support/TidyUpMyFiles/settings.yaml` |
| Activity and undo data | `~/Library/Application Support/TidyUpMyFiles/activity.sqlite` |
| Readable activity logs | `~/Library/Logs/TidyUpMyFiles/activity-YYYY-MM.log` |
| AI API keys | login Keychain, service "TidyUpMyFiles AI" |

## Permissions

- **Desktop, Documents, Downloads**: macOS asks the first time the app reads them.
- **Full Disk Access**: only for Smart Trash (reading `~/.Trash`) and, on some macOS versions, for undoing
  a move to the Trash. System Settings → Privacy & Security → Full Disk Access.
- **Launch at login** uses `SMAppService` and works only when running from `TidyUpMyFiles.app`.

## Automation hooks

- `TidyUpMyFilesApp --screenshot shot.png` opens the main window without taking focus, saves a picture
  and quits (the watcher stays off). `TIDYUP_START_SECTION` (overview, rules, preview, activity,
  smartTrash, ai, general) picks the screen; with `preview` it runs a read-only simulation.
  `TIDYUP_SHOT_DELAY=<seconds>` changes when the picture is taken.
- `TIDYUP_SHOT_SCENE` (with `--screenshot`) stages states for documentation pictures, such as
  `rule-editor`, `rules-folder`, `report`, `menu`, `ai-suggestions`, `preview-folded`.
- `TIDYUP_DEMO_HOME` and `TIDYUP_HOME`: see [CLI.md](CLI.md#environment).
- AI agents connect through `tidyup mcp`: see [MCP.md](MCP.md). Rule changes they make are saved to
  `rules.yaml`, and the running app reloads the file when it changes outside the app.
