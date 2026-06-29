# Input AI Recommendation Runtime Refactor

## Summary

- Extract real-time AI recommendation request lifecycle from
  `InputControllerCoordinator` into `InputAIRecommendationRuntime`.
- Keep behavior unchanged while reducing coordinator responsibility for active
  request ids, generations, task cancellation, stale-result checks, and
  diagnostics.

## Scope

- Add `InputAIRecommendationRuntime` under `Sources/KnowTypeInputMethod`.
- Keep `Sources/KnowTypeAI/AIRecommendationRuntime.swift` as the provider-layer
  runtime; this PR only adds the IMK-side scheduling/runtime boundary.
- Keep candidate-panel rendering, Rime behavior, AI provider prompts, accepted
  feedback tracking, and settings unchanged.

## Implementation

- The coordinator builds `InputAIRecommendationRuntimeContext` from the current
  raw input, locked prefix, runtime preferences, app bundle id, locale,
  composition id, raw revision, lexical context, and accepted-feedback context.
- `InputAIRecommendationRuntime` asks `InputAIRecommendationSchedulePolicy`
  before creating any provider task, then builds `AIRecommendationRequest`
  without real-time Rime candidate hints.
- Async AI results publish state only after request id, generation, composition
  id, raw revision, and raw input still match the current composition snapshot.
- Reset, close, invalidation, and reschedule paths preserve existing
  cancellation and stale-result diagnostic stages.

## Test Plan

- `swift test --quiet --filter InputAIRecommendationRuntimeTests`
- `swift test --quiet --filter InputAIRecommendationSchedulePolicyTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is a refactor-only PR.
- The coordinator remains the owner of final `aiRecommendationState` because
  candidate panel state and commit shortcuts still read that slot.
