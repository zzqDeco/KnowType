# Traditional Lexicon Extension

## Summary

This slice prepares the local Chinese engine for a larger, authorized lexicon without importing third-party dictionary data into the repository.

The engine keeps its small clean-room seed lexicon, but callers can now inject additional lexicon entries through a public data model. `TraditionalInputEngine` folds those entries into the same private index used by seed entries, so spaced pinyin, compact pinyin, duplicate-key merging, known-token detection, and partial-prefix lookup all share one code path.

## Scope

- Add `TraditionalInputLexiconEntry` and `TraditionalInputLexiconOutput` as the stable data shape for local lexicon resources.
- Add `TraditionalInputEngine(additionalLexiconEntries:)` while preserving the existing default initializer behavior.
- Normalize injected pinyin tokens by trimming whitespace and lowercasing them.
- Ignore empty injected entries instead of letting malformed resource rows affect parsing.
- Keep `LexiconIndex` private; external data never bypasses parser validation, duplicate merging, or partial-match caps.
- Make compact segmentation derive known tokens from the active engine instance, not only from the built-in seed table.
- Keep cloud fallback policy unchanged: if an injected local lexicon resolves the input, unknown-initial cloud completion is not used.

## Non-Goals

- Do not import Squirrel, Rime, McBopomofo, vChewing, or other third-party dictionary data in this PR.
- Do not add a file loader or settings UI yet.
- Do not change AI continuation behavior.

## Tests

- Additional entries work for both spaced and compact pinyin.
- Ambiguous compact inputs such as `xian` can still surface an injected `xi an` phrase without reopening arbitrary initial-only splits.
- Duplicate pinyin keys keep the highest-confidence output.
- Malformed empty entries are ignored.
- Broad partial lookup over a synthetic large lexicon remains capped.
- Correction fallback does not call the provider when the additional local lexicon already resolves the input.
