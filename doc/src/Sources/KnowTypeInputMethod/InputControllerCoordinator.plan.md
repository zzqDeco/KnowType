# InputControllerCoordinator

`InputControllerCoordinator` owns the testable state machine behind `KnowTypeInputController`.

Current behavior:

- maps `InputKeyStroke` values through `InputKeyCommandMapper`
- owns the composing raw buffer, `CompositionBuffer`, composition id, input mode runtime, local and async suggestions, native candidate selection, and candidate panel state
- writes marked text through `InputControllerClient.setMarkedText`, using raw pinyin plus resolved segment display text rather than eagerly replacing the composition with the first Chinese candidate
- commits through `InputControllerClient.insertText` using the active marked range when available
- maps Return/Enter to raw commit and keeps segment selection inside the marked composition until a full commit action is reached
- publishes raw marked text synchronously, then computes local prefix and segment candidates through a cancellable background task
- coalesces candidate panel refreshes so anchor resolution and AppKit panel layout run after the key event returns
- keeps `Space` tied to the visible candidate snapshot for the current raw input; while candidates are still pending it commits the current raw/composition display instead of synchronously computing a hidden fallback
- keeps `Tab` and visible shortcut `2` tied to a ready AI recommendation only; pending, disabled, unavailable, and ineligible AI states keep the composition
- keeps pending Space and punctuation commits non-blocking when the user has already resolved part of the composition; they commit the current displayed composition and do not run segment fallback synchronously
- when native Rime is active, keeps visible candidate selection authoritative: segment/continuation/fully-resolved composition paths run before native Space, and a non-highlighted prefix/full row selected in the custom panel is committed through Rime's stable candidate index before the generic native Space path
- records committed typing events through `AIContextEventRecording` after insert decisions, while external Delete events are logged only when no composition is active
- rejects stale async candidate publications by raw input, composition id, composition buffer, cancellation state, and suggestion generation
- uses `InputTaskSupervisor` to replace stale local-candidate, AI, panel-render, and runtime-lexicon tasks
- rejects stale AI publications by raw input, composition id, and AI generation
- warms or refreshes runtime lexicon engines in the background with generation checks; synchronous lexicon reload remains available only for deterministic test/offline paths
- clears composition state for cancel and commit while hiding the candidate panel through `InputControllerHost`
- flushes user selection history on deactivate and close; close also hides the panel
- schedules delayed candidate re-anchor through `InputControllerHost` and applies only the latest same-raw-input, same-composition reanchor
- keeps provider-backed suggestion publication guarded by `SuggestionPublicationGuard`
- suppresses AI recommendation while the composition is only partially resolved, so half-pinyin marked text is not sent as a locked prefix

The coordinator remains IMK-free. Production host/client adapters live beside the IMK wrapper, while tests use fake clients, fake host scheduling, fake panel capture, and fake history persistence.
