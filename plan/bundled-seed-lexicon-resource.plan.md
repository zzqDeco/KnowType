# Bundled Seed Lexicon Resource

## Summary

This slice moves the clean-room MVP seed lexicon out of Swift source and into a package resource.

The goal is not to import a large third-party dictionary. The goal is to make the current seed lexicon use the same resource, catalog, and index path that future authorized dictionaries will use.

## Scope

- Add `Resources/TraditionalLexicon/seed.tsv` to `KnowTypeCore`.
- Load the seed resource through `TraditionalInputLexiconFileSource`.
- Package SwiftPM resource bundles into the installable IMK app bundle.
- Keep `TraditionalInputEngine()` behavior unchanged for current MVP cases.
- Add tests proving the seed resource loads without diagnostics and still powers default Chinese decoding.
- Do not add external dictionary data in this PR.

## Tests

- Seed resource loads from `Bundle.module` without diagnostics.
- Default `TraditionalInputEngine` still decodes core MVP examples such as `wsm` and `nishishei`.
- Existing engine tests continue to pass through the resource-backed seed lexicon.
