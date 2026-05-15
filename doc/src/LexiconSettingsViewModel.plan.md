# LexiconSettingsViewModel

`LexiconSettingsViewModel` is the SwiftUI settings model for local lexicon directory status.

- It reports directories from `KNOWTYPE_LEXICON_DIR`, `KNOWTYPE_LEXICON_DIRS`, and the default user lexicon directory under Application Support.
- It loads existing directories through `TraditionalInputLexiconFileSource`.
- It summarizes loaded entry counts, resource file counts, and typed diagnostics.
- Missing directories are shown as missing but are not treated as errors.

The model does not import the input-method frontend. It depends on `KnowTypeCore` so settings status uses the same JSON/TSV parser as the runtime input engine.
