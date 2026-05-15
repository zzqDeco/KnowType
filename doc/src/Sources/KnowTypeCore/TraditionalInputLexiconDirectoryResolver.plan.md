# TraditionalInputLexiconDirectoryResolver

`TraditionalInputLexiconDirectoryResolver` owns local lexicon directory discovery for both the input method and settings app.

- It exposes the stable environment variable keys `KNOWTYPE_LEXICON_DIR` and `KNOWTYPE_LEXICON_DIRS`.
- It resolves environment-provided directories before the default Application Support directory.
- It trims empty environment paths and de-duplicates standardized file paths while preserving order.
- It returns URLs only; it does not create directories, scan resources, load dictionaries, or own dictionary licensing.

The input-method runtime uses this resolver before loading authorized JSON/TSV resources into `TraditionalInputEngine`. The settings app uses the same resolver before reporting directory status or creating missing directories on explicit user action.
