# InputAIAcceptanceRuntime

## Responsibility

`InputAIAcceptanceRuntime` owns the IMK-side post-commit AI acceptance
side effects.

It receives coordinator-provided commit context, records accepted AI learning,
records typing-context events, and coordinates accepted-feedback span tracking
without touching marked text, candidate presentation, Rime state, or host
insertion.

## Boundaries

- It may call `AIContextEventRecording`, `AIAcceptedLearningRecording`, and
  `AIAcceptedFeedbackTracker`.
- It may record privacy-safe `AIRecommendationDiagnosticEvent` values for
  protected accepted-learning and feedback-tracking skips.
- It must not call `insertText`, `setMarkedText`, Rime APIs, candidate-panel
  APIs, lexical-profile refresh, or settings persistence.

## Behavior Notes

- Accepted AI learning records are written only when the accepted AI candidate's
  display text exactly matches the committed text.
- Protected app contexts skip accepted learning and accepted-feedback tracking.
- Secret-like committed text or raw input suppresses typing-context events and
  the lexical-commit effect that is later consumed by
  `InputLexicalCommitRuntime`.
- Accepted-feedback tracking is armed before insertion and verified after the
  delayed post-insert caret check.
- External Delete events are recorded only when AI context recording is
  available, AI recommendations are possible, and cloud continuation is enabled.

## Tests

- `InputAIAcceptanceRuntimeTests`
- `AIAcceptedFeedbackTrackerTests`
- `InputControllerCoordinatorTests`
- `swift test`
