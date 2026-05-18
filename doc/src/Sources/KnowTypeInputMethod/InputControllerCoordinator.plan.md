# InputControllerCoordinator

`InputControllerCoordinator` owns the testable state machine behind `KnowTypeInputController`.

Current behavior:

- maps `InputKeyStroke` values through `InputKeyCommandMapper`
- owns the composing raw buffer, `CompositionBuffer`, composition id, input mode runtime, local and async suggestions, native candidate selection, and candidate panel state
- writes marked text through `InputControllerClient.setMarkedText`, using raw pinyin plus resolved segment display text rather than eagerly replacing the composition with the first Chinese candidate
- commits through `InputControllerClient.insertText` using the active marked range when available
- maps Return/Enter to raw commit and keeps segment selection inside the marked composition until a full commit action is reached
- publishes raw marked text and a raw candidate panel state synchronously, then refreshes correction candidates asynchronously in production
- uses a bounded local commit fallback for Space and punctuation while async candidates are still pending, so commit keys do not insert raw pinyin just because a background suggestion has not published yet
- applies the best local remaining segment before pending Space or punctuation commits when the user has already resolved part of the composition
- rolls back pending punctuation fallback when the remaining local segment cannot fully resolve the composition, preserving the visible partially resolved marked text
- lets Tab and raw-input shortcuts use local pending snapshots while async candidates are still loading
- keeps local fallback continuations available after a fully resolved segmented composition when no cloud provider is configured
- rejects stale async candidate publications by raw input, composition id, composition buffer, cancellation state, and suggestion generation
- warms or refreshes runtime lexicon engines in the background with generation checks; synchronous lexicon reload remains available only for deterministic test/offline paths
- clears composition state for cancel and commit while hiding the candidate panel through `InputControllerHost`
- flushes user selection history on deactivate and close; close also hides the panel
- schedules delayed candidate re-anchor through `InputControllerHost` and applies it only when raw input and composition id still match
- keeps provider-backed suggestion publication guarded by `SuggestionPublicationGuard`
- suppresses provider continuation while the composition is only partially resolved, so half-pinyin marked text is not sent as a locked prefix

The coordinator remains IMK-free. Production host/client adapters live beside the IMK wrapper, while tests use fake clients, fake host scheduling, fake panel capture, and fake history persistence.
