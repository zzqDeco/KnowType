# InputController

`KnowTypeInputController` is the thin `IMKInputController` wrapper for the macOS input method bundle.

Current behavior:

- adapts `IMKTextInput` clients into the internal `InputControllerClient` seam
- forwards IMK text, key event, candidate, commit, palette, deactivate, and close callbacks into `InputControllerCoordinator`
- keeps AppKit/InputMethodKit imports guarded by `canImport(InputMethodKit)`
- owns the production `CandidatePanelWindowController` and exposes it through the host seam
- starts the coordinator with the bundled seed engine so enabling the input source does not synchronously parse user-installed lexicon files on the IMK main path
- preserves superclass calls for `hidePalettes`, `deactivateServer`, `inputControllerWillClose`, and fallback composition updates

The controller should stay small. Product input behavior, marked text writes, commit replacement ranges, lifecycle flushing, and delayed re-anchor gating belong in `InputControllerCoordinator` so they can be covered by unit tests without installing a real Text Input Source.
