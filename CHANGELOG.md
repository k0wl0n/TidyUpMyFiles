# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com).
Each release's notes on [GitHub Releases](../../releases) are generated from the commits and are the full record.

## [Unreleased]

### Added

- Rules per watched folder with nested AND / OR / NOT conditions and ordered actions: move, copy,
  rename with tokens, tags, color labels, zip, unzip, alias, Shortcuts, Trash, open and opt-in shell scripts.
- Ready-made rules that can be added to any folder; each card shows where it is already used.
- One-button Overview: Scan looks first, See results opens Preview, then Undo.
- Preview showing every file's from → to, name clashes and new folders before anything runs.
- Activity log grouped by run, monthly text logs, CSV export and one-click Undo.
- Real-time folder watching that waits for downloads to finish.
- Smart Trash, optional AI suggestions (local or bring your own key), YAML import/export and the
  `tidyup` command.
- MCP server (`tidyup mcp`) so AI agents can list rules, simulate, tidy, undo and add ready-made rules;
  `tidyup` now ships inside the app.
- The app reloads its rules when they are changed outside it, such as by `tidyup` or an AI agent.
- `AGENTS.md`, `CLAUDE.md` and project skills for coding agents.
- Release workflow: DMG and command line downloads with checksums and build provenance, and a Homebrew
  formula and cask.

### Fixed

- A folder is never moved, copied or packed into itself; AI suggestions only cover files.
- Big Preview lists fold once the scan results arrive.
