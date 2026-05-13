# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- candidate panel view model
- custom candidate selection policy for raw/prefix numeric shortcuts
- candidate anchor range policy for IMK clients with known or unknown selection ranges
- custom AppKit candidate presentation styled as a compact macOS candidate list
- candidate panel renderer with raw input, locked prefix, and continuation rows
- shortcut-to-commit behavior
- async suggestion pipeline wiring
- Level 0 no-provider routing for protected input
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`
- `KnowTypeInputMethodApp` bundle entry assembled by `scripts/build-inputmethod-bundle.sh`

The AppKit candidate panel is the active candidate presentation for the IMK bundle. This avoids the `IMKCandidates` failure mode where the system panel accepts data but does not become visible in some host apps. Prefix rows are rendered first, continuation rows after them, and raw input is rendered only while no suggestion exists.

The IMK controller directly marks composing text with `IMKTextInput.setMarkedText` and replaces the active marked range on commit. Candidate anchor lookup prefers marked range end, falls back to selected range and line-height rectangle, then uses pointer location so the candidate window remains visible when a host app cannot expose caret geometry.

MVP manual acceptance still must verify candidate window behavior in host apps because IMK text input behavior varies across AppKit, browser, Electron, and terminal contexts.
