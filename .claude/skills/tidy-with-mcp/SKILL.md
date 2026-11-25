---
name: tidy-with-mcp
description: Tidy the person's folders through the TidyUpMyFiles MCP tools (list_rules, simulate, run, undo...). Use when asked to clean up, sort or organise Downloads, Desktop or Documents and the tidyup MCP server is connected.
---

# Tidy folders with the TidyUpMyFiles tools

Always look before you act, and keep the person in charge.

1. **Look.** `list_rules` to see the watched folders and which rules are live. If there are none,
   `list_templates` and suggest suitable ready-made rules.
2. **Simulate.** `simulate` the folder and tell the person, in plain words, what would move where
   (group by destination; mention anything going to the Trash).
3. **Ask before changing anything.** Only after they agree:
   - add rules with `add_template` (they arrive in preview mode),
   - `run` the folder. It acts on live rules only; pass `include_preview: true` only when the person
     wants the previewed moves done now,
   - or `set_rule_mode` to `live` if they want that rule to keep tidying by itself.
4. **Report.** Say what moved and give the run number. Offer `undo` (with `batch`) if anything looks wrong.

Never work around a refusal (system folders, `~/Library`, `.git` folders and apps are off-limits), and
never try to delete files: the Trash is as far as anything goes.
