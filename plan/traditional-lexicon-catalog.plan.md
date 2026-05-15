# Traditional Lexicon Catalog

## Summary

This slice composes multiple authorized lexicon resources into one local engine input while preserving per-resource diagnostics.

The resource loader parses a single JSON or TSV file. The catalog loader is the next boundary: it lets KnowType load bundled, user, or generated resources together, keep valid resources active, and report exactly which resource failed validation.

## Scope

- Add `TraditionalInputLexiconResource` to name a resource, carry its format, and hold its data.
- Add `TraditionalInputLexiconDiagnostic` for typed per-resource failures.
- Add `TraditionalInputLexiconCatalog` as the combined entries plus diagnostics result.
- Add `TraditionalInputLexiconCatalogLoader` that loads resources independently and keeps valid entries when another resource fails.
- Add `TraditionalInputLexiconCatalog.makeEngine()` so downstream code can build `TraditionalInputEngine` without reimplementing the injection call.

## Tests

- Multiple JSON/TSV resources load into one catalog and feed the engine.
- A bad resource produces a diagnostic without dropping valid resources.
- Resource order is preserved for deterministic downstream ranking.
