# InputLexicalCommitRuntime

## Responsibility

`InputLexicalCommitRuntime` owns the input-method boundary for local lexical
commit and selection side effects.

It combines `InputSelectionHistoryRuntime`, `LexicalProfileRuntime`, and a
bounded in-process recent commit buffer so `InputControllerCoordinator` can
record selection or commit facts without directly managing lexical profile
refresh parameters.

## Boundaries

- It may trim committed text, maintain the recent commit buffer, call
  `InputSelectionHistoryRuntime`, request lexical context snapshots, and
  schedule or cancel lexical profile refreshes.
- It returns `InputRuntimeEvent` values for the coordinator to publish through
  `InputEventBus`.
- It must not call Rime conversion, host insertion, marked-text APIs,
  candidate-panel publication, AI recommendation scheduling, or AI acceptance
  learning.

## Behavior Notes

- Commit text is trimmed before recording. Empty trimmed commits do not publish
  events or schedule lexical refresh.
- Recent commits are capped at 32 entries by default.
- Selection recording preserves `InputSelectionHistoryRuntime` protected-input
  filtering, recent selection cache, and persistence semantics.
- Lexical profile refresh receives only the current runtime's bounded recent
  commits and in-process recent selection history.

## Tests

- `InputLexicalCommitRuntimeTests`
- `InputSelectionHistoryRuntimeTests`
- `LexicalProfileRuntimeTests`
- `InputControllerCoordinatorTests`
- `swift test`
