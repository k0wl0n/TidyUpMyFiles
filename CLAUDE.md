@AGENTS.md

## Claude Code

- Project skills are in `.claude/skills/` (add a ready-made rule, add a condition or action, check a
  release, tidy with the MCP tools). Use them for those jobs.
- To try the MCP server from this checkout: `swift build --product tidyup`, then
  `claude mcp add tidyup-dev -e TIDYUP_DEMO_HOME=/tmp/tidyup-demo -- "$(swift build --show-bin-path)/tidyup" mcp`.
  The demo home keeps real files out of reach while testing.
