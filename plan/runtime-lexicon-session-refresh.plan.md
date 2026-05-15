# Runtime Lexicon Session Refresh

## Summary

This fix lets the already-running IMK front end notice local lexicon directory changes at safe composition boundaries.

The previous runtime path could load new JSON/TSV files when a new default engine was requested, but an already-created `KnowTypeInputController` still held the engine and session controller built during initialization. This branch adds a lightweight directory snapshot and refreshes the runtime engine only when a new composition starts and the snapshot changed.

## Scope

- Add runtime lexicon snapshots for directory existence and JSON/TSV resource file metadata.
- Ignore hidden files, unsupported extensions, and directories in the snapshot, matching the file-source contract.
- Rebuild the input-method traditional engine and session controller at the start of a new composition only when the snapshot changed.
- Keep mid-composition behavior stable; active marked text is not reinterpreted after each key.
- Do not add file-system watchers or per-keystroke engine reloads.

## Test Plan

- `swift test --filter InputMethodLexiconRuntimeTests`
- `swift test`
- `git diff --check`
