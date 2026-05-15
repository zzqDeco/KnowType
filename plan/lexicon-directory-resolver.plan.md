# Lexicon Directory Resolver

## Summary

This slice moves local lexicon directory discovery into `KnowTypeCore` so the input method runtime and settings app share the same source of truth.

The behavior stays the same: KnowType resolves `KNOWTYPE_LEXICON_DIR`, colon-separated `KNOWTYPE_LEXICON_DIRS`, and the default `~/Library/Application Support/KnowType/Lexicons` directory, then de-duplicates standardized file paths.

## Scope

- Add `TraditionalInputLexiconDirectoryResolver` in `KnowTypeCore`.
- Keep existing environment variable names stable.
- Keep environment-provided directories before the Application Support directory.
- Reuse the resolver from `InputMethodLexiconRuntime`.
- Reuse the resolver from `LexiconSettingsViewModel`.
- Preserve missing-directory behavior; directory creation remains a settings action, not automatic input-method startup behavior.
- Do not change lexicon parsing, ranking, candidate paging, or provider behavior.

## Test Plan

- `swift test --filter TraditionalInputLexiconDirectoryResolverTests`
- `swift test --filter InputMethodLexiconRuntimeTests`
- `swift test --filter LexiconSettingsViewModelTests`
- `swift test`
- `git diff --check`
