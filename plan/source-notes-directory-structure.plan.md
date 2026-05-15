# Source Notes Directory Structure

## Goal

Make `doc/src` follow the same ownership boundaries as the repository instead of keeping all source notes in one flat directory.

## Behavior

- Swift target notes live under `doc/src/Sources/<target>/`.
- Shell tooling notes live under `doc/src/scripts/`.
- Target-level overview notes use `README.plan.md` inside the matching target directory.
- `doc/src/README.md` is the canonical index and explains the mirroring rule.
- Agent guidance points future source notes to `doc/src/<repo-path>/...plan.md`.

## Verification

```bash
git diff --check
find doc/src -type f | sort
rg -n "doc/src/[^ ]+\\.plan\\.md|\\]\\([^)]*\\.plan\\.md\\)" doc AGENTS.md
```
