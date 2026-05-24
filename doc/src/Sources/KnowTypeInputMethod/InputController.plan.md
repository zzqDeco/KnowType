# InputController

`KnowTypeInputController` is the thin `IMKInputController` wrapper for the macOS input method bundle.

Current behavior:

- adapts `IMKTextInput` clients into the internal `InputControllerClient` seam
- forwards IMK text, key event, candidate, commit, palette, deactivate, and close callbacks into `InputControllerCoordinator`
- keeps AppKit/InputMethodKit imports guarded by `canImport(InputMethodKit)`
- owns the production `CandidatePanelWindowController` and exposes it through the host seam
- starts the coordinator without `InputMethodLexiconRuntime`; production Chinese conversion is Rime-only and must not build `TraditionalInputEngine` during controller startup
- injects a process-wide lexical profile store, refresh gate, and Rime userdb snapshot provider so multiple IMK controller sessions cannot independently overwrite the global `LEXICAL_PROFILE.md`
- overrides `showPreferences(_:)` and retains `KnowTypePreferencesWindowController`, so the input-method menu opens the SwiftUI settings window without relying on InputMethodKit's default nib-backed preferences loader
- builds its input-method menu through `KnowTypeInputMethodMenuBuilder`: `AI Continuation`, log/support/Rime folders, `KnowType Settings...`, and About
- toggles `AI Continuation` by writing `InputMethodRuntimePreferences` and forcing the coordinator to reload runtime preferences and refresh the visible candidate UI for the external menu change
- preserves superclass calls for `hidePalettes`, `deactivateServer`, `inputControllerWillClose`, and fallback composition updates

The controller should stay small. Product input behavior, marked text writes, commit replacement ranges, lifecycle flushing, and delayed re-anchor gating belong in `InputControllerCoordinator` so they can be covered by unit tests without installing a real Text Input Source.
