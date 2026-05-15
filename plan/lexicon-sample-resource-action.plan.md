# Lexicon Sample Resource Action

## Summary

This slice adds a small settings action that creates a valid sample TSV lexicon resource in the first configured local lexicon directory.

The goal is pragmatic: after users create or inspect the local lexicon directory, they should have a deterministic way to generate a known-good file and immediately verify that the JSON/TSV loader and runtime refresh path are working.

## Scope

- Add `LexiconSettingsViewModel.createSampleLexiconResource()`.
- Create missing target directory parents when the sample action is explicitly invoked.
- Write `knowtype-sample.tsv` only when it does not already exist.
- Refresh status after create, no-op, or error.
- Add a Lexicons settings button for the sample TSV action.
- Keep external dictionary import, licensing workflow, and bulk lexicon management out of this slice.

## Test Plan

- `swift test --filter LexiconSettingsViewModelTests`
- `swift test`
- `git diff --check`
