# Use TidyUpMyFiles from AI agents (MCP)

TidyUpMyFiles includes a [Model Context Protocol](https://modelcontextprotocol.io) server, so AI apps
such as Claude Code, Claude Desktop, Cursor or Codex can look at your rules, simulate, tidy and undo
— with the same rules, history and safety rules as the app. It runs on your Mac over stdio; nothing
goes online.

The server is the `tidyup mcp` command. After `./scripts/build-app.sh` it is inside the app:

```
/Applications/TidyUpMyFiles.app/Contents/MacOS/tidyup mcp
```

(or `build/tidyup mcp` if you didn't move the app to Applications).

## Connect it

**Claude Code**

```sh
claude mcp add tidyup -- /Applications/TidyUpMyFiles.app/Contents/MacOS/tidyup mcp
```

**Claude Desktop** — Settings → Developer → Edit Config, then add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "tidyup": {
      "command": "/Applications/TidyUpMyFiles.app/Contents/MacOS/tidyup",
      "args": ["mcp"]
    }
  }
}
```

**Cursor** — the same `mcpServers` block in `~/.cursor/mcp.json`.

**Codex** — in `~/.codex/config.toml`:

```toml
[mcp_servers.tidyup]
command = "/Applications/TidyUpMyFiles.app/Contents/MacOS/tidyup"
args = ["mcp"]
```

Restart the AI app afterwards. Ask it something like *"What would TidyUpMyFiles do with my Downloads?"*

## Tools

| Tool | What it does | Changes files? |
| --- | --- | --- |
| `list_rules` | watched folders and their rules, on/off, preview/live | no |
| `list_templates` | ready-made rules and the folders that use them | no |
| `simulate` | what the rules would do to a folder right now | no |
| `activity_log` | recent steps, each file's from → to | no |
| `add_template` | add a ready-made rule to a folder, in preview mode | rules only |
| `set_rule_mode` | switch a rule between preview and live | rules only |
| `run` | tidy a folder now with the live rules (`include_preview` for the others too) | yes, undoable |
| `undo` | take back the last step or a whole run | yes |

## Safety

- `run` only acts on **live** rules unless the agent passes `include_preview: true`. It is marked
  destructive, so AI apps ask you before using it.
- Nothing is deleted for good (removed files go to the Trash), and every run can be undone with `undo`
  or from the app's Activity screen.
- System folders, `~/Library`, `.git` folders and apps are refused, whatever the agent asks.
- Rule changes are saved to `rules.yaml`; the app notices and reloads them within a few seconds.
