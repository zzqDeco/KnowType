# InputControllerCoordinator

`InputControllerCoordinator` owns the testable state machine behind `KnowTypeInputController`.

Current behavior:

- maps `InputKeyStroke` values through `InputKeyCommandMapper`
- owns the composing raw buffer, composition id, input mode runtime, local and async suggestions, native candidate selection, and candidate panel state
- writes marked text through `InputControllerClient.setMarkedText`
- commits through `InputControllerClient.insertText` using the active marked range when available
- clears composition state for cancel and commit while hiding the candidate panel through `InputControllerHost`
- flushes user selection history on deactivate and close; close also hides the panel
- schedules delayed candidate re-anchor through `InputControllerHost` and applies it only when raw input and composition id still match
- keeps provider-backed suggestion publication guarded by `SuggestionPublicationGuard`

The coordinator remains IMK-free. Production host/client adapters live beside the IMK wrapper, while tests use fake clients, fake host scheduling, fake panel capture, and fake history persistence.
