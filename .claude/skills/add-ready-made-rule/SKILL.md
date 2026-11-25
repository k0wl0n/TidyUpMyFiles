---
name: add-ready-made-rule
description: Add or change a ready-made rule (template) in TidyUpMyFiles, such as "sort e-books from Downloads". Use when asked for a new template, a new recommended rule, or a change to an existing one.
---

# Add a ready-made rule

Ready-made rules live in `Sources/TidyUpMyFilesCore/Storage/Templates.swift`.

1. **Add it to `catalog`.** The list order is the priority order: rules higher up win when several match.
   Keep duplicates first and the dated "old downloads" archive last.
   - A plain "this kind of file goes there" rule: use `sortByKind(id, title, kind, to:)`.
   - Anything else: `Template(id:title:detail:folderPath:rule:)`. `detail` is one plain sentence ending
     in "→ destination". Rules start in preview mode; don't set `mode: .live`.
   - `id` is permanent (it is saved in people's `rules.yaml` as `template:`). Never rename an id.
2. **Changing an existing one?** Add its old actions to `previousVersions[id]` so untouched copies on
   people's Macs are upgraded and edited copies are left alone.
3. **Icon and colour:** add a `case` to `TemplateStyle` in `Sources/TidyUpMyFilesApp/OverviewView.swift`
   (an SF Symbol and a theme gradient).
4. **Tests** in `Tests/TidyUpMyFilesCoreTests/TemplateTests.swift`: a sample file matches the new rule,
   the destination is right, and it lands in the right place in the catalog order. Use `SandboxTestCase`.
5. **Docs:** the recommended-rules sentence in `README.md` (Features), the rule list in
   `docs/USER-GUIDE.md` if it names them, and `CHANGELOG.md`.
6. `swift build` (no warnings) and `swift test`.

Check in demo mode before calling it done:

```sh
TIDYUP_DEMO_HOME=/tmp/tidyup-demo "$(swift build --show-bin-path)/tidyup" templates add
TIDYUP_DEMO_HOME=/tmp/tidyup-demo "$(swift build --show-bin-path)/tidyup" sim
```
