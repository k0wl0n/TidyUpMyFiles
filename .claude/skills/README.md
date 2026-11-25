# Project skills

Step-by-step instructions that coding agents (Claude Code and others that read `AGENTS.md`) load when a
job matches their description.

| Skill | Use it to |
| --- | --- |
| [add-ready-made-rule](add-ready-made-rule/SKILL.md) | add or change a ready-made rule |
| [add-condition-or-action](add-condition-or-action/SKILL.md) | add a rule condition or action end to end |
| [release-check](release-check/SKILL.md) | check a build is ready to publish |
| [tidy-with-mcp](tidy-with-mcp/SKILL.md) | tidy folders safely through the MCP tools |

## Add a skill

Make a folder named after the skill (lowercase, dashes) with a `SKILL.md` like this:

```markdown
---
name: my-skill
description: What it does and when to use it, in one or two sentences. Agents choose skills by this line.
---

# Title

1. The steps, naming the exact files and commands.
2. What must stay true (the safety rules in AGENTS.md).
3. How to check it worked: tests, demo-mode commands, docs to update.
```
