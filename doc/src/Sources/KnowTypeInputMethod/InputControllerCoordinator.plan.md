# InputControllerCoordinator

`InputControllerCoordinator` owns the testable state machine behind `KnowTypeInputController`.

Current behavior:

- maps `InputKeyStroke` values through `InputKeyCommandMapper`
- owns the composing raw buffer, `CompositionBuffer`, composition id, input mode runtime, Rime snapshots, native candidate selection, and candidate panel state
- writes marked text through `InputControllerClient.setMarkedText`, using raw pinyin/preedit while Rime owns candidate conversion and commit decisions
- commits through `InputControllerClient.insertText` using the active marked range when available
- maps Return/Enter to raw commit; retired local segment selection is no longer generated on the production IMK path
- publishes raw marked text and current-page Rime candidates synchronously
- cancels any pending retired local-candidate task before synchronous native candidate publication, so an older background snapshot cannot overwrite a fresh native state update
- coalesces candidate panel refreshes so anchor resolution and AppKit panel layout run after the key event returns
- keeps `Space` tied to the visible candidate snapshot for the current raw input; while candidates are still pending it commits the current raw/composition display instead of synchronously computing a hidden fallback
- keeps `Tab` and visible shortcut `2` tied to a ready AI recommendation only; pending, disabled, unavailable, and ineligible AI states keep the composition
- when native Rime is active, keeps visible candidate selection authoritative: a non-highlighted prefix/full row selected in the custom panel is committed through Rime's current-page candidate index before the generic native Space path
- explicit native `PageUp`/`PageDown` are forwarded to the conversion engine while composition is active, independent of custom candidate-panel visibility
- when native Rime is active, arrow navigation moves inside the current page first, then maps right/down at the page edge to Rime `.pageDown` and left/up at the page edge to Rime `.pageUp`
- handles Rime's default paging punctuation (`-`/`=`, `,`/`.`) before symbol commit fallback, but falls back to punctuation when the native snapshot does not change so page-boundary punctuation is not swallowed
- native candidate mapping uses the encoded current-page index when present; ambiguous duplicate text without an index does not fall back to the retired local converter
- records committed typing events through `AIContextEventRecording` after insert decisions, while external Delete events are logged only when no composition is active
- rejects stale async candidate publications by raw input, composition id, composition buffer, cancellation state, and suggestion generation
- uses `InputTaskSupervisor` to replace stale local-candidate cancellation tokens, AI, and panel-render tasks
- rejects stale AI publications by raw input, composition id, and AI generation
- does not initialize or rebuild runtime lexicon engines in the IMK product path; Rime is the only production conversion source
- clears composition state for cancel and commit while hiding the candidate panel through `InputControllerHost`
- resets the conversion engine when Delete clears the raw buffer, including native raw-bypass state from non-ASCII compositions
- flushes user selection history on deactivate and close; close also hides the panel
- schedules delayed candidate re-anchor through `InputControllerHost` and applies only the latest same-raw-input, same-composition reanchor
- keeps provider-backed suggestion publication guarded by `SuggestionPublicationGuard`
- suppresses AI recommendation while the composition is only partially resolved, so half-pinyin marked text is not sent as a locked prefix

The coordinator remains IMK-free. Production host/client adapters live beside the IMK wrapper, while tests use fake clients, fake host scheduling, fake panel capture, and fake history persistence.
