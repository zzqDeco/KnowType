# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- candidate panel view model
- custom candidate selection policy for raw/prefix numeric shortcuts
- candidate anchor range policy for IMK clients with known or unknown selection ranges
- native `IMKCandidates` presentation with custom AppKit fallback
- candidate panel renderer with raw input, locked prefix, and continuation rows
- shortcut-to-commit behavior
- async suggestion pipeline wiring
- Level 0 no-provider routing for protected input
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`
- `KnowTypeInputMethodApp` bundle entry assembled by `scripts/build-inputmethod-bundle.sh`

The native `IMKCandidates` panel is the active candidate presentation for the IMK bundle. It receives prefix and continuation rows from `InputCandidateListBuilder`, while `KnowTypeInputController` maps continuation selections back into prefix-locked commits. The custom panel is retained only as a fallback and is hidden whenever native candidates are shown.

The IMK controller directly marks composing text with `IMKTextInput.setMarkedText` and replaces the active marked range on commit. Candidate anchor lookup now falls back from selected range to marked range and line-height rectangle so the candidate window can follow the caret in more host apps.

MVP manual acceptance still must verify candidate window behavior in host apps because IMK text input behavior varies across AppKit, browser, Electron, and terminal contexts.
