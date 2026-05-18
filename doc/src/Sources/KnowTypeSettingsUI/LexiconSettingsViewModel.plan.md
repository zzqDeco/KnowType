# LexiconSettingsViewModel

`LexiconSettingsViewModel` is the SwiftUI settings model for local lexicon directory status.

- It reports directories resolved by `TraditionalInputLexiconDirectoryResolver`.
- It loads existing directories through `TraditionalInputLexiconFileSource`.
- It summarizes loaded entry counts, resource file counts, and typed diagnostics.
- Missing directories are shown as missing but are not treated as errors.
- It can create missing lexicon directories and refresh status afterward.
- It can create a non-overwriting `knowtype-sample.tsv` file in the first configured directory so users can verify local lexicon loading.
- It can install the recommended managed lexicon pack on explicit user action.
- It displays installed `*.metadata.json` pack records while keeping those metadata files out of lexicon resource counts.

The model does not import the input-method frontend. It depends on `KnowTypeCore` so settings status uses the same JSON/TSV parser as the runtime input engine.
