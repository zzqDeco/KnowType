# LexiconSettingsPresentation

`LexiconSettingsPresentation.swift` contains testable presentation structs for the Lexicons settings tab.

## Responsibilities

- Map total lexicon entry counts, refresh state, action labels, and last action messages into display state.
- Show the create-missing-directories action only when at least one configured lexicon directory is missing.
- Map each `LexiconDirectoryStatus` into status, resource-file count, loaded-entry count, path, and diagnostic rows.
- Keep JSON/TSV format guidance text in one test-covered source of truth.

The presenters do not read files or create directories. `LexiconSettingsViewModel` remains responsible for loading lexicon status and performing refresh/create actions.
