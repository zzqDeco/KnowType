# TraditionalInputLexiconFileSource

`TraditionalInputLexiconFileSource` loads local lexicon resources from disk.

- It infers `.json` and `.tsv` formats case-insensitively.
- It can load an explicit file list or scan one directory.
- Directory scans are sorted by filename for deterministic resource order.
- Hidden files are skipped during directory scans.
- Known managed-pack metadata filenames are skipped so installed pack metadata is not parsed as dictionary JSON.
- Unsupported extensions and unreadable files are reported as diagnostics.
- Valid resources remain active when another file fails.

This type is the filesystem boundary. Parsing remains in `TraditionalInputLexiconResourceLoader`; multi-resource composition remains in `TraditionalInputLexiconCatalogLoader`.
