# Security policy

TidyUpMyFiles moves, renames and trashes files, so safety bugs matter to us. Examples: a rule touching
a folder it should never touch, a file being lost instead of going to the Trash, an action that can't be
undone, or an AI key leaving the Keychain.

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's private
[security advisory form](../../security/advisories/new) for this repository instead, with:

- what happened and what you expected,
- the steps or the `rules.yaml` that cause it,
- your macOS version and the app version.

We aim to reply within a week and will credit you in the release notes unless you'd rather we didn't.

## Supported versions

Only the latest release gets security fixes.
