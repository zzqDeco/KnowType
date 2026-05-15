# Traditional Lexicon File Source

## Summary

This slice connects the local lexicon catalog to real JSON/TSV files without adding any third-party dictionary data.

The file source infers resource format from file extensions, reads file data, delegates parsing to the catalog loader, and preserves diagnostics for unreadable, unsupported, or invalid files. This gives the settings app and future bundled-resource path a deterministic way to build a `TraditionalInputEngine` from audited resources.

## Scope

- Add `TraditionalInputLexiconFileSource`.
- Infer `.json` and `.tsv` resource formats case-insensitively.
- Load explicit file lists while preserving valid entries when another file fails.
- Load a directory in stable filename order.
- Skip hidden files in directory loading.
- Report unsupported and unreadable files as typed diagnostics.
- Keep external dictionary data out of this PR.

## Tests

- Format inference is case-insensitive.
- JSON and TSV files build a catalog and feed the engine.
- Unsupported, unreadable, and invalid files produce diagnostics without dropping valid entries.
- Directory loading is deterministic and skips hidden files.
