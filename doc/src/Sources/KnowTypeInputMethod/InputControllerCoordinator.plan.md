# InputControllerCoordinator

`InputControllerCoordinator` owns the testable state machine behind `KnowTypeInputController`.

Current behavior:

- maps `InputKeyStroke` values through `InputKeyCommandMapper`
- owns the composing raw buffer, `CompositionBuffer`, composition id, input mode runtime, local and async suggestions, native candidate selection, and candidate panel state
- writes marked text through `InputControllerClient.setMarkedText`, using raw pinyin plus resolved segment display text rather than eagerly replacing the composition with the first Chinese candidate
- commits through `InputControllerClient.insertText` using the active marked range when available
- maps Return/Enter to raw commit and keeps segment selection inside the marked composition until a full commit action is reached
- clears composition state for cancel and commit while hiding the candidate panel through `InputControllerHost`
- flushes user selection history on deactivate and close; close also hides the panel
- schedules delayed candidate re-anchor through `InputControllerHost` and applies it only when raw input and composition id still match
- keeps provider-backed suggestion publication guarded by `SuggestionPublicationGuard`
- suppresses provider continuation while the composition is only partially resolved, so half-pinyin marked text is not sent as a locked prefix

The coordinator remains IMK-free. Production host/client adapters live beside the IMK wrapper, while tests use fake clients, fake host scheduling, fake panel capture, and fake history persistence.
