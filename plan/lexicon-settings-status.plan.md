# Lexicon Settings Status

## Summary

This slice exposes the local lexicon runtime path in the SwiftUI settings app. Users can see the directory KnowType reads for local JSON/TSV lexicons, whether it exists, how many resources were found, how many entries loaded, and whether any resource produced diagnostics.

## Scope

- Add a settings-side `LexiconSettingsViewModel`.
- Reuse `TraditionalInputLexiconFileSource` and typed diagnostics from `KnowTypeCore`.
- Add a `Lexicons` settings tab with read-only status and a manual refresh button.
- Show the same environment-variable and Application Support directories used by the runtime loader.
- Keep the input method runtime path unchanged.
- Do not add external dictionary data or import UI.

## Test Plan

- `swift test --filter LexiconSettingsViewModelTests`
- `swift test`
- `git diff --check`
