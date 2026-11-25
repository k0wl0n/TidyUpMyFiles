# Contributing

Thanks for helping make TidyUpMyFiles better! Bug reports, ideas and pull requests are all welcome.

## Before you start

- For anything bigger than a small fix, open an issue first so we can agree on the approach.
- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code fits together and the safety rules
  every change must keep.

## Development

Requirements: macOS 13 or later, Xcode 16 or later (Swift 5.9+).

```sh
swift build
swift test
./scripts/build-app.sh      # TidyUpMyFiles.app and the tidyup command in ./build
```

Try changes safely with demo mode, which keeps `~`, the Trash, settings and logs inside a throwaway folder:

```sh
mkdir -p /tmp/tidyup-demo/Downloads        # put some sample files in here
TIDYUP_DEMO_HOME=/tmp/tidyup-demo "$(swift build --show-bin-path)/TidyUpMyFilesApp"
```

## Rules for changes

- **Safety first.** Never delete files permanently (Trash only), keep every action undoable, and never
  touch system folders, `~/Library`, `.git` folders or app bundles.
- **Tests use temporary folders only**, never the real home folder or the real Trash.
- **No new warnings.** The package builds with strict concurrency checking.
- **Dependencies** are pinned to exact versions in `Package.resolved`; new ones need a good reason.
- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org): lowercase and
  imperative, e.g. `fix(preview): keep the folded state after a rescan`.
- Update the docs when behaviour changes. If a screen changes, mention it in the pull request; the
  maintainers refresh the pictures in `.github/assets/` (small JPGs, about 1600 px wide).
- Coding agents: see [AGENTS.md](AGENTS.md) and the project skills in [.claude/skills](.claude/skills/README.md).

## Releasing

Maintainers: **Actions → release → Run workflow**. With `auto`, the version comes from the commits since the
last tag (`feat!` or `BREAKING CHANGE:` → major, minor while still 0.x; `feat` → minor; `fix`/`perf` → patch;
anything else alone → no release). The workflow tests, builds the DMG and command line archive, records
build provenance, tags `vX.Y.Z` and publishes the GitHub release with notes. If the `HOMEBREW_TAP_TOKEN`
secret is set (a fine-grained token with Contents read/write on `homebrew-tap` only), it also updates
`Formula/tidyup.rb` and `Casks/tidyupmyfiles.rb` there. Check what the next version would be locally with
`scripts/next-version.sh`.

## License

By contributing you agree that your work is released under the [MIT license](LICENSE).
