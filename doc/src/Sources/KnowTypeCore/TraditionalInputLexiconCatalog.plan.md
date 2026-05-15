# TraditionalInputLexiconCatalog

`TraditionalInputLexiconCatalog` is the composition layer for local lexicon resources.

- `TraditionalInputLexiconResource` names one resource and carries its format and raw data.
- `TraditionalInputLexiconCatalogLoader` loads each resource independently through `TraditionalInputLexiconResourceLoader`.
- Valid entries are kept even when another resource fails validation.
- Failures are reported as `TraditionalInputLexiconDiagnostic` values with the resource id and typed loader error.
- Entry order is preserved across resources so later ranking remains deterministic.
- `makeEngine()` builds a `TraditionalInputEngine` from catalog entries.

The catalog does not own dictionary licensing decisions. Only audited or user-owned resources should be passed into it.
