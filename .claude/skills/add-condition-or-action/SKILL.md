---
name: add-condition-or-action
description: Add a new rule condition (what to look for) or action (what to do) to TidyUpMyFiles, end to end — model, YAML, engine, executor, undo, preview, editor UI, tests and docs.
---

# Add a condition or an action

Work through every layer; a half-added condition or action breaks loading, preview or undo.

## A new condition

1. `Sources/TidyUpMyFilesCore/Model/Condition.swift` — add the case (and any match type).
2. `Sources/TidyUpMyFilesCore/Model/Coding.swift` — its YAML key and value, both directions.
3. `Sources/TidyUpMyFilesCore/Engine/FileFacts.swift` — the fact it needs. If reading it is slow
   (Spotlight, file contents, hashing), add a `FactNeeds` flag and set it in `FactNeeds.forRules`, so it
   is only read when a rule uses it.
4. `Sources/TidyUpMyFilesCore/Engine/RuleEngine.swift` — evaluate it.
5. `Sources/TidyUpMyFilesApp/ConditionEditor.swift` — let people pick and edit it.

## A new action

1. `Sources/TidyUpMyFilesCore/Model/Rule.swift` — the `Action` case and its `verb`.
2. `Sources/TidyUpMyFilesCore/Model/Coding.swift` — YAML.
3. `Sources/TidyUpMyFilesCore/Engine/RuleEngine.swift` — `step(for:)`: the planned target and the summary
   text people see in Preview.
4. `Sources/TidyUpMyFilesCore/Execution/ActionExecutor.swift` — do it. Call `guardrail.check`, respect
   `ConflictPolicy`, never delete (use the `TrashProvider`), and log a record **with `UndoInfo`**.
5. `Sources/TidyUpMyFilesCore/Execution/UndoService.swift` — undo it.
6. `Sources/TidyUpMyFilesCore/Execution/PreviewInspector.swift` — predicted clashes and new folders.
7. `Sources/TidyUpMyFilesApp/ActionEditor.swift` — the editor row.
8. Anything that runs other programs (like shell scripts and Shortcuts) must be off by default behind a
   setting in `AppSettings`.

## Both

- Tests (`SandboxTestCase`, temporary folders and the fake Trash only): YAML round trip, matching or
  doing it, and undo putting everything back.
- Docs: the tables in `docs/RULES.md`, the Features list in `README.md`, `CHANGELOG.md`.
- `swift build` with no warnings, then `swift test`.
