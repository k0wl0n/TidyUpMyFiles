# Rules reference

Rules live in `~/Library/Application Support/TidyUpMyFiles/rules.yaml`. The app's rule editor writes this
file for you; you can also edit it by hand, or import and export it from **Settings → General**.
Check a hand-edited file with `tidyup validate`.

## How rules run

- Each watched folder has its own list of rules, checked **top to bottom**. The first rule that matches
  wins, unless it says `continue_matching: true`.
- New rules start in **preview** mode: matches wait in Preview until you approve them. Set `mode: live`
  to let a rule act on its own.
- Actions run in order. A step that can't run (a missing folder, a name clash set to `skip`) is logged
  and the rest of that rule stops.

## Example

```yaml
version: 1
folders:
  - path: ~/Desktop
    enabled: true
    rules:
      - name: Screenshots
        enabled: true
        mode: live                 # preview (default) | live
        when:
          all:
            - any:
                - name: { starts_with: "Screenshot" }
                - name: { starts_with: "Screen Shot" }
            - kind: image
        do:
          - move: "~/Pictures/Screenshots/{added.year}-{added.month}"
            on_conflict: rename      # skip | rename | rename_existing | overwrite (needs allow_overwrite: true)
  - path: ~/Downloads
    exclude: ["*.part", "Keep*"]   # never touched by any rule in this folder
    rules:
      - name: Old installers
        when:
          all:
            - extension: [dmg, pkg]
            - age_days: { gt: 7 }
        do:
          - trash: true
      - name: Invoices
        continue_matching: true
        when:
          all:
            - kind: pdf
            - not: { name: { contains: "draft" } }
            - source_url: { contains: "billing" }
        do:
          - rename: "{added:yyyy-MM-dd} {name}.{ext}"
          - move: Invoices/{added.year}   # relative = inside the watched folder
          - add_tags: [Finance]
```

## Conditions

| Condition | Values |
| --- | --- |
| `name`, `source_url` | `contains`, `starts_with`, `ends_with`, `equals`, `regex`, `glob`, `case_sensitive` |
| `extension` | a list, e.g. `[jpg, png]` |
| `kind` | image, pdf, archive, installer, document, spreadsheet, presentation, code, ebook, font, video, audio, folder, other |
| `size` | `gt` / `gte` / `lt` / `lte` / `eq`, in bytes or like `"10 MB"` |
| `created`, `modified`, `added`, `last_opened`, `taken` (photo date) | `before`, `after` (`yyyy-MM-dd`), `older_than_days`, `newer_than_days` |
| `age_days` | same comparisons as `size` |
| `tag` | `has`, `lacks` |
| `color` | gray, green, purple, blue, yellow, red, orange |
| `is_folder`, `empty`, `duplicate` | `true` |
| `contents` | text inside the file (plain text, PDF, Word, RTF); same matches as `name` |

Group conditions with `all` (AND), `any` (OR) and `not`, nested as deep as you like.

## Actions

| Action | Notes |
| --- | --- |
| `move`, `copy` | a folder; `create_folders` (default true), `on_conflict` |
| `rename` | a pattern with tokens; `on_conflict` |
| `add_tags`, `remove_tags` | a list of Finder tags |
| `set_color` | a Finder color label |
| `archive` | zip it: `true` = next to the item, or a folder |
| `extract` | unpack .zip and .tar archives: `true` = next to the archive, or a folder |
| `alias` | make a Finder alias in a folder |
| `shortcut` | run a Shortcut with the file (turn on **Allow Shortcuts** in Settings) |
| `trash` | move to the Trash (never deleted for good) |
| `open` | open with the default app |
| `shell` | run a script (turn on **Allow shell scripts** in Settings); the item's path is in `$TIDYUP_FILE` |

`on_conflict`: `rename` (add a number to the new file), `rename_existing` (move the old file aside),
`skip`, or `overwrite` (only with `allow_overwrite: true` on the rule; the replaced file goes to the Trash).

## Name tokens

`{name}`, `{ext}`, `{kind}`, `{counter}`, `{date:FORMAT}`, `{created:FORMAT}`, `{modified:FORMAT}`,
`{added:FORMAT}`, `{taken:FORMAT}` (Unicode date patterns such as `yyyy-MM-dd`), and
`{date|created|modified|added|taken}.{year|month|day|monthname}`.
