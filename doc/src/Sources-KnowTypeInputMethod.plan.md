# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- candidate panel view model
- custom candidate selection policy for raw/prefix numeric shortcuts
- candidate anchor range policy for IMK clients with known or unknown selection ranges
- custom AppKit candidate panel window
- candidate panel renderer with raw input, locked prefix, and continuation rows
- shortcut-to-commit behavior
- async suggestion pipeline wiring
- Level 0 no-provider routing for protected input
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`
- `KnowTypeInputMethodApp` bundle entry assembled by `scripts/build-inputmethod-bundle.sh`

The custom panel is the active candidate presentation for the IMK bundle. Native `IMKCandidates` remains available only as protocol surface for legacy candidate callbacks; KnowType avoids showing both panels at once.

MVP manual acceptance still must verify candidate window behavior in host apps because IMK text input behavior varies across AppKit, browser, Electron, and terminal contexts.
