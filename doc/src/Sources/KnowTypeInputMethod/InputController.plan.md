# InputController

`KnowTypeInputController` is the thin `IMKInputController` wrapper for the macOS input method bundle.

Current behavior:

- adapts `IMKTextInput` clients into the internal `InputControllerClient` seam
- injects one process-wide `ProcessInputModeStateRuntime` into every coordinator
  so app and window changes cannot reload different text or punctuation modes;
  a new host process starts linked Chinese mode with the saved global width
- forwards key-input callbacks with only the callback sender's adapted client;
  the coordinator decides whether active composition may use the current IMK
  client fallback, while idle printable input with a missing sender remains
  pass-through
- uses current-client fallback for lifecycle-style callbacks such as explicit
  commit, candidate selection, deactivate, and close where finishing or
  clearing an existing composition is safer than dropping state
- returns exactly the `keyDown` mask from `recognizedEvents(_:)`, allowing
  InputMethodKit to retain its default click-outside composition commit;
  modifier-dependent shortcuts read flags from key-down events and do not
  require separate `keyUp` or `flagsChanged` registration
- forwards IMK text, key event, candidate, commit, palette, deactivate, and close callbacks into `InputControllerCoordinator`
- keeps AppKit/InputMethodKit imports guarded by `canImport(InputMethodKit)`
- owns the production `CandidatePanelWindowController` and exposes it through the host seam
- implements delayed host scheduling only for candidate-panel re-anchor and a
  separate next-main-queue scheduling path for post-insert AI feedback caret
  verification
- starts the coordinator without `InputMethodLexiconRuntime`; production Chinese conversion is Rime-only and must not build `TraditionalInputEngine` during controller startup
- schedules a process-wide native Rime session prewarm on a utility task after
  controller initialization; this does not change `RimeConversionEngine`'s
  read-only construction semantics, and a very early first key can still use the
  normal lazy synchronous session creation path
- keeps controller construction read-only for provider and AI user data:
  provider loading, AI recommendation runtime documents, AI context memory, and
  accepted learning/feedback writes stay lazy until real input, AI scheduling,
  or explicit maintenance occurs; Rime native session prewarm is the explicit
  post-init performance exception, and selection history opens in no-create mode
  and only writes after a real candidate selection
- constructs the lazy default AI recommendation provider with provider-layer
  debounce disabled; IMK-side request timing is owned by
  `InputAIRecommendationRuntime`, which debounces before transport dispatch and
  stale-drops older provider results instead of aborting started HTTP requests
- injects a process-wide lexical profile store, refresh gate, and Rime userdb snapshot provider so multiple IMK controller sessions cannot independently overwrite the global `LEXICAL_PROFILE.md`
- injects one process-wide `AIContextMemoryRuntime` actor into every controller,
  so multiple IMK sessions cannot digest or archive the same pending context
  snapshot independently
- overrides `showPreferences(_:)` and retains `KnowTypePreferencesWindowController`, so the input-method menu opens the SwiftUI settings window without relying on InputMethodKit's default nib-backed preferences loader
- builds its input-method menu through `KnowTypeInputMethodMenuBuilder`:
  localized AI continuation, current shared input-mode status,
  log/support/Rime folders, settings, and About items
- toggles localized AI continuation by writing `InputMethodRuntimePreferences` and forcing the coordinator to reload runtime preferences and refresh the visible candidate UI for the external menu change
- preserves superclass calls for `hidePalettes`, `deactivateServer`, `inputControllerWillClose`, and fallback composition updates

The controller should stay small. Product input behavior, marked text writes, commit replacement ranges, lifecycle flushing, and delayed re-anchor gating belong in `InputControllerCoordinator` so they can be covered by unit tests without installing a real Text Input Source.

Set `KNOWTYPE_STARTUP_DEBUG=1` to log controller init timing, Rime prewarm
timing, and lazy runtime state without recording user text.
