# Input AI Acceptance Runtime Refactor

## Summary

- Extract post-commit AI accepted-learning, typing-context event recording, and
  accepted-feedback tracking orchestration from `InputControllerCoordinator`
  into `InputAIAcceptanceRuntime`.
- Keep input behavior unchanged while reducing coordinator responsibility for
  AI acceptance side effects.

## Scope

- Add `InputAIAcceptanceRuntime` under `Sources/KnowTypeInputMethod`.
- Keep `AIAcceptedFeedbackTracker` as the low-level span tracker.
- Keep host writes, Rime behavior, candidate-panel state, AI recommendation
  scheduling, and provider prompts unchanged.

## Implementation

- The coordinator builds commit and feedback contexts from the current raw
  input, schema id, app bundle id, selected candidate source, accepted AI
  candidate, delete count, and client.
- `InputAIAcceptanceRuntime` records accepted AI history only for explicit AI
  candidates whose display text matches the committed text.
- Protected app contexts skip accepted learning and feedback tracking with the
  existing diagnostic stages.
- Secret-like raw input or committed text suppresses typing-context events and
  the lexical-commit effect that is now consumed by
  `InputLexicalCommitRuntime`.
- The insert sequence remains prepare feedback tracking, record commit side
  effects, insert text, delayed post-insert caret verification, then reset.

## Test Plan

- `swift test --quiet --filter InputAIAcceptanceRuntimeTests`
- `swift test --quiet --filter AIAcceptedFeedbackTrackerTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputAIRecommendationRuntimeTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is an input-method runtime boundary refactor.
- Lexical profile refresh moved later to `InputLexicalCommitRuntime`; this
  acceptance runtime still does not access profile refresh directly.
- The new runtime does not access host insertion, marked text, Rime selection,
  candidate-panel state, or settings persistence.
