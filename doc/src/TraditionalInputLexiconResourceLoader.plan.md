# TraditionalInputLexiconResourceLoader

`TraditionalInputLexiconResourceLoader` is the clean boundary between audited lexicon files and the local Chinese input engine.

- It parses JSON resources directly into `[TraditionalInputLexiconEntry]`.
- It parses TSV rows in `pinyin<TAB>text<TAB>confidence` form; confidence is optional and defaults to `0.72`.
- It ignores blank TSV lines and comment lines beginning with `#`.
- It normalizes pinyin tokens by trimming and lowercasing them.
- It trims output text and rejects empty outputs.
- It rejects non-finite or out-of-range confidence values.
- It returns typed errors so bad resource rows are visible during build, test, or settings import flows.

The loader does not merge duplicate entries itself. Duplicate-key merging remains inside `TraditionalInputEngine` and `LexiconIndex`, keeping all lexicon sources on the same ranking path.
