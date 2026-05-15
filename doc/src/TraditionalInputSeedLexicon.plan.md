# TraditionalInputSeedLexicon

`TraditionalInputSeedLexicon` is the packaged clean-room seed dictionary for the local Chinese input engine.

- It reads `seed.tsv` from the `KnowType_KnowTypeCore.bundle` SwiftPM resource bundle.
- It checks the signed app `Contents/Resources` location before falling back to SwiftPM build/test locations.
- It delegates file reading to `TraditionalInputLexiconFileSource`.
- It returns a `TraditionalInputLexiconCatalog`, so missing or invalid resources surface as typed diagnostics.
- `TraditionalInputEngine()` uses these entries as its default lexicon before applying caller-provided local entries.

The resource is intentionally small and license-clean. Larger dictionaries must still enter through the authorized local lexicon resource path after review.
