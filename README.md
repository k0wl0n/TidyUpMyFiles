<div align="center">
  <img src=".github/assets/icon.png" width="112" alt="TidyUpMyFiles">

  <h1>TidyUpMyFiles</h1>

  <p><strong>A free, open-source file organizer for macOS.</strong></p>

  <p>Organize your files automatically. Preview changes. Undo with confidence.</p>

  <img src="https://img.shields.io/badge/macOS-13%2B-blue?style=flat-square" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat-square" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">

  <p>
    <a href="../../releases/latest">Download</a> ·
    <a href="#installation">Installation</a> ·
    <a href="#features">Features</a> ·
    <a href="#documentation">Documentation</a>
  </p>

  <img src=".github/assets/tour.gif" width="820" alt="TidyUpMyFiles tour: scan a messy Downloads folder, preview every move, tidy and undo on macOS">

  <p><sub>Silent preview · <a href="https://github.com/k0wl0n/TidyUpMyFiles/releases/download/v0.1.0/TidyUpMyFiles-promo.mp4">Download the 37-second video with sound (MP4)</a></sub></p>
</div>

## About

TidyUpMyFiles is a native macOS menu bar app that automatically organizes your
Downloads, Desktop, Documents, and other selected folders using customizable rules.

Move screenshots into dated folders, organize PDFs, clean up old installers,
and keep your files where they belong — without doing it manually.

Free and open source. No subscription, no account, and no telemetry.
Works offline by default.

## Installation

### Homebrew

Install the macOS application:

```sh
brew install --cask k0wl0n/tap/tidyupmyfiles
```

Or install only the command-line tool:

```sh
brew install k0wl0n/tap/tidyup
```

### Direct download

1. Download `TidyUpMyFiles-x.y.z.dmg` from the
   [latest release](../../releases/latest).
2. Open the DMG and drag TidyUpMyFiles into **Applications**.
3. Open the application and grant access to the folders you want to organize.

TidyUpMyFiles is available for Apple Silicon and Intel Macs running
macOS 13 Ventura or later.

> [!NOTE]
> The application is not yet notarized by Apple. On the first launch,
> macOS may prevent it from opening.
>
> After verifying the download, go to **System Settings → Privacy & Security**
> and select **Open Anyway**.

<details>
<summary>Alternative installation command</summary>

After verifying the downloaded application, you can remove its
quarantine attribute:

```sh
xattr -dr com.apple.quarantine /Applications/TidyUpMyFiles.app
```

Full Disk Access is only required for the Smart Trash feature.

</details>

<details>
<summary>Verify your download</summary>

Compare the downloaded file against the release checksums:

```sh
shasum -a 256 -c checksums.txt
```

Verify that the DMG was built by this repository's release workflow:

```sh
gh attestation verify TidyUpMyFiles-x.y.z.dmg \
  --repo k0wl0n/TidyUpMyFiles
```

You can also [build the application from source](#build-from-source).

</details>

## Why TidyUpMyFiles?

| | |
| :--- | :--- |
| **Automatic organization** | Keep your folders organized with rules that run automatically. |
| **Visual rule editor** | Create powerful rules without writing code. |
| **Preview before running** | See exactly what will happen before applying new rules. |
| **Undo and activity history** | Track changes and undo supported file operations. |
| **Privacy first** | No account, no telemetry, and offline by default. |
| **Free and open source** | Every feature is included under the MIT license. |

## How it works

| Step | Description |
| :--- | :--- |
| **01 — Scan** | Scan your selected folders without changing any files. |
| **02 — Preview** | Review proposed changes and select which files to organize. |
| **03 — Tidy** | Apply selected changes or enable Live mode for automatic organization. |
| **04 — Undo** | Review your activity history and undo supported operations when needed. |

### Example rules

| When | Action |
| :--- | :--- |
| A new screenshot is detected | Move to `Pictures/Screenshots/2026-11` |
| A PDF is downloaded | Move to `Documents/PDF` |
| An installer is older than 7 days | Move to Trash |
| A video is downloaded | Move to `Movies/Downloads` |
| A duplicate file is detected | Move to Trash |
| A ZIP archive is downloaded | Extract into a selected folder |

Use the included rule templates or create your own.

## Features

### File organization

- Monitor Downloads, Desktop, Documents, and custom folders.
- Create folder-specific rules with nested AND, OR, and NOT conditions.
- Match files by name, extension, type, size, date, Finder tags, download
  source, file contents, and duplicates.
- Combine multiple actions: move, copy, rename, tag, compress, extract,
  create aliases, open files, and move to Trash.
- Rename files dynamically using tokens such as `{added.year}`.
- Use ready-made templates for common file types.
- Automatically organize new files after downloads have finished.

### Safety and control

- New rules start in Preview mode.
- Review source and destination paths before applying changes.
- Handle filename conflicts by renaming, skipping, or explicitly allowing
  replacement.
- Undo supported operations individually or by an entire run.
- Protect system folders, `~/Library`, `.git` directories, and applications.
- Review activity history with monthly logs and CSV export.
- Receive optional notifications after background operations.
- Use Smart Trash to review and permanently remove old Trash items.

### Privacy

- Works offline without an account.
- No analytics or telemetry.
- AI suggestions are optional and disabled by default.
- Use a local AI model with Ollama or configure your own API key.
- External AI services may receive filenames when enabled.
- AI-generated suggestions require approval before being applied.

### Developer and AI integration

- Import and export rules using YAML.
- Manage files from the terminal using the `tidyup` command.
- Run simulations before applying changes.
- Connect AI agents through the Model Context Protocol (MCP).
- Integrate with Claude Code, Claude Desktop, Cursor, and Codex.
- Run macOS Shortcuts and opt-in shell scripts as rule actions.

## Screenshots

### Rule editor and preview

<table>
  <tr>
    <td width="50%" align="center">
      <img src=".github/assets/03-rule-editor.jpg" width="400" alt="Visual rule editor">
    </td>
    <td width="50%" align="center">
      <img src=".github/assets/04-preview-detail.jpg" width="400" alt="File operation preview">
    </td>
  </tr>
  <tr>
    <td align="center">
      <strong>Visual Rule Editor</strong><br>
      Create custom rules without code.
    </td>
    <td align="center">
      <strong>Preview Changes</strong><br>
      See exactly where your files will go.
    </td>
  </tr>
</table>

### Activity and undo

<div align="center">
  <img src=".github/assets/06-activity-runs.jpg" width="720" alt="Activity history and undo">
  <p>Review previous runs, track file changes, and undo supported operations.</p>
</div>

### Menu bar

<div align="center">
  <img src=".github/assets/11-menu-bar.jpg" width="260" alt="TidyUpMyFiles menu bar">
  <p>Scan folders and manage automation directly from the macOS menu bar.</p>
</div>

## Command-line interface

TidyUpMyFiles includes a command-line tool for terminal workflows and automation.

| Command | Description |
| :--- | :--- |
| `tidyup sim` | Preview file operations without applying changes. |
| `tidyup run` | Run configured rules. |
| `tidyup undo` | Undo supported operations. |
| `tidyup log` | View activity history. |
| `tidyup templates` | Browse available rule templates. |
| `tidyup mcp` | Start the MCP server for AI agents. |

See the [CLI documentation](docs/CLI.md) for usage and available options.

## AI agent integration

TidyUpMyFiles supports the Model Context Protocol (MCP), allowing AI agents
to interact with the application using its existing rules and safety controls.

Supported clients include:

- Claude Code
- Claude Desktop
- Cursor
- Codex

Agents can simulate file operations, apply rules, review activity,
and undo supported changes.

See the [MCP setup guide](docs/MCP.md) to get started.

## Documentation

| Document | Description |
| :--- | :--- |
| [User Guide](docs/USER-GUIDE.md) | Learn how to use the application, create rules, and enable automation. |
| [Rules Reference](docs/RULES.md) | Available conditions, actions, YAML configuration, and naming tokens. |
| [Command Line](docs/CLI.md) | CLI commands and usage examples. |
| [MCP Integration](docs/MCP.md) | Connect TidyUpMyFiles to AI agents. |
| [Architecture](docs/ARCHITECTURE.md) | Application architecture, safety model, storage, and permissions. |
| [Changelog](CHANGELOG.md) | Release history, improvements, and fixes. |

## Build from source

### Requirements

- macOS 13 Ventura or later
- Xcode 16 or later
- Swift 5.9 or later

Clone the repository:

```sh
git clone https://github.com/k0wl0n/TidyUpMyFiles.git
cd TidyUpMyFiles
```

Build and run tests:

```sh
swift build
swift test
```

Build the universal macOS application:

```sh
./scripts/build-app.sh
```

The application and CLI binary are available in `./build`.

<details>
<summary>Dependencies and reproducible builds</summary>

Dependencies are pinned in `Package.resolved`, including Yams 6.2.2.

CI uses:

```sh
--only-use-versions-from-resolved-file
```

Dependabot waits seven days before proposing dependency updates.

</details>

<details>
<summary>Create release artifacts</summary>

Build the application, DMG, command-line archive, and checksums:

```sh
VERSION=1.2.0 ./scripts/build-app.sh
VERSION=1.2.0 ./scripts/make-dmg.sh
```

Replace `1.2.0` with the intended release version.

</details>

<details>
<summary>Code signing and notarization</summary>

An Apple Developer ID is required to sign and notarize the application.

Configure your signing identity:

```sh
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

Create a notarization credential profile:

```sh
xcrun notarytool store-credentials notary
```

Configure the notarization profile:

```sh
export NOTARY_PROFILE=notary
```

Run the release build:

```sh
VERSION=1.2.0 ./scripts/build-app.sh
VERSION=1.2.0 ./scripts/make-dmg.sh
```

The scripts handle signing, notarization, and stapling when the required
credentials are configured.

</details>

## FAQ

<details>
<summary><strong>Is TidyUpMyFiles free?</strong></summary>

Yes. TidyUpMyFiles is completely free and open source under the MIT license.
There are no subscriptions, trials, accounts, or locked features.

</details>

<details>
<summary><strong>Is it an alternative to Hazel?</strong></summary>

Yes. TidyUpMyFiles provides rule-based file organization with a visual rule
editor, automatic folder monitoring, previews, and activity history.

It is designed as a free, open-source alternative for macOS users.

</details>

<details>
<summary><strong>How do I automatically organize my Downloads folder?</strong></summary>

Open TidyUpMyFiles, select your Downloads folder, and add the included
rule templates.

Scan the folder, review the proposed changes, and apply them.
Switch approved rules to Live mode to organize new downloads automatically.

</details>

<details>
<summary><strong>Can TidyUpMyFiles delete my files?</strong></summary>

Standard cleanup rules move files to Trash instead of permanently deleting them.

Smart Trash can permanently remove items after review. Explicit replacement
actions and custom shell scripts may also have irreversible effects.

Always review rules before enabling automatic execution.

</details>

<details>
<summary><strong>Can I undo file operations?</strong></summary>

Supported file operations can be undone from the Activity screen,
either individually or by an entire run.

Permanent deletion and some external actions cannot be undone.

</details>

<details>
<summary><strong>Does it require an internet connection?</strong></summary>

No. Core file organization features work offline.

An internet connection may be required if you enable an external AI service.
Local AI suggestions can run through Ollama.

</details>

<details>
<summary><strong>Can I use it with AI agents?</strong></summary>

Yes. TidyUpMyFiles provides an MCP server that allows supported AI agents
to simulate, organize, and undo file operations.

See the [MCP documentation](docs/MCP.md).

</details>

<details>
<summary><strong>Which macOS versions are supported?</strong></summary>

macOS 13 Ventura or later, on both Apple Silicon and Intel Macs.

</details>

<details>
<summary><strong>Why does macOS prevent the application from opening?</strong></summary>

The application is not yet notarized by Apple.

After verifying the download, open **System Settings → Privacy & Security**
and select **Open Anyway**.

Alternatively, you can build the application from source.

</details>

## Contributing

Contributions, bug reports, and feature requests are welcome.

- Read the [Contributing Guide](CONTRIBUTING.md).
- Check existing [issues](../../issues) before opening a new one.
- Submit improvements through pull requests.
- Report security and safety issues privately through [SECURITY.md](SECURITY.md).

For contributors using AI coding agents:

- [AGENTS.md](AGENTS.md) — project instructions for coding agents.
- [CLAUDE.md](CLAUDE.md) — Claude Code instructions.
- [Project Skills](.claude/skills/README.md) — reusable development workflows.

## License

TidyUpMyFiles is released under the [MIT License](LICENSE).

See [Third-Party Notices](THIRD_PARTY_NOTICES.md) for dependency licenses.

---

<div align="center">
  <img src=".github/assets/icon.png" width="48" alt="TidyUpMyFiles">

  <p><strong>Less clutter. More control.</strong></p>

  <p>
    <a href="../../releases/latest">Download</a> ·
    <a href="docs/USER-GUIDE.md">Documentation</a> ·
    <a href="../../issues">Report an Issue</a>
  </p>

  <p>Free and open source, built for macOS.</p>
</div>