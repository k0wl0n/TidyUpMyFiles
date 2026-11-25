# Command line (`tidyup`)

`tidyup` uses the same rules file, settings and history as the app. Build it with
`./scripts/build-app.sh` and copy `build/tidyup` somewhere on your `PATH`.

```sh
tidyup templates                # list the ready-made rules
tidyup templates add            # add the missing ones (preview mode)
tidyup validate                 # check rules.yaml
tidyup sim [~/Downloads]        # what would happen; changes nothing
tidyup run [~/Downloads]        # act on live rules (add --include-preview for preview rules too)
tidyup undo [--batch 12]        # undo the last action or a whole run
tidyup log --search invoice     # activity log (--limit N)
tidyup mcp                      # serve AI agents over MCP (see MCP.md)
```

Every command accepts `--rules FILE` to use another rules file.

## Environment

| Variable | Effect |
| --- | --- |
| `TIDYUP_HOME=/some/folder` | keep rules, settings and history in another folder |
| `TIDYUP_DEMO_HOME=/some/folder` | demo mode: `~`, the Trash, settings and logs all live inside that folder |
