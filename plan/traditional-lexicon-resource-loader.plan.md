# Traditional Lexicon Resource Loader

## Summary

This slice turns the lexicon-extension API into a resource-ready path without importing third-party dictionary data.

KnowType can now parse authorized local lexicon resources into `TraditionalInputLexiconEntry` values. The loader supports JSON for structured bundled resources and TSV for simple generated or audited word lists. Loaded entries still go through `TraditionalInputEngine` normalization, indexing, duplicate merging, and compact parsing.

## Scope

- Add `TraditionalInputLexiconResourceLoader`.
- Support JSON resources shaped as `[TraditionalInputLexiconEntry]`.
- Support TSV resources with `pinyin<TAB>text<TAB>confidence` and optional confidence.
- Ignore blank TSV lines and `#` comments.
- Normalize pinyin tokens and output text.
- Reject malformed rows with typed errors instead of silently polluting the engine.
- Keep external dictionary data out of this PR.

## Tests

- JSON entries normalize and feed the engine.
- TSV comments, default confidence, and explicit confidence parse correctly.
- Format dispatch calls the right parser.
- Invalid UTF-8, invalid column counts, and invalid confidence produce typed errors.
