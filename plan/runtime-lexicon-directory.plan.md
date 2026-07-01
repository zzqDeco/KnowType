# Runtime Lexicon Directory

## Summary

This slice connects the input-method pipeline to user-owned local lexicon directories.

The engine already knows how to parse JSON/TSV resources and merge them into the same index as the bundled seed lexicon. The missing runtime step is a stable input-method entry point that can load authorized files from disk without changing Swift source or sending data to providers.

## Scope

- Add `InputMethodLexiconRuntime` in the input-method layer.
- Load JSON/TSV files from explicit local directories through `TraditionalInputLexiconFileSource`.
- Support `KNOWTYPE_LEXICON_DIR` and `KNOWTYPE_LEXICON_DIRS` for development and local smoke tests.
- Include the default user directory `~/Library/Application Support/KnowType/Lexicons`.
- Let `SessionSuggestionPipeline` and `InputSessionController` accept a runtime-built `TraditionalInputEngine`.
- Keep missing directories silent so a fresh install behaves like the bundled seed engine.
- Do not add external dictionary data in this PR.

## Tests

- Environment directory parsing is deterministic and de-duplicates paths.
- A local TSV directory feeds the traditional engine.
- Missing directories do not produce diagnostics.
- `SessionSuggestionPipeline` can use a runtime lexicon engine for prefix candidates.
