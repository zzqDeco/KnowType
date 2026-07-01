# InputAIRecommendationRuntime

## Responsibility

`InputAIRecommendationRuntime` owns the IMK-side lifecycle for real-time AI
recommendation requests.

It builds `AIRecommendationRequest` values from coordinator-provided input
context, records privacy-safe diagnostics, tracks the active request id and
generation, cancels stale tasks, and publishes matching `AIRecommendationState`
updates back to the coordinator.

## Boundaries

- It may call the injected `AIRecommendationProviding` runtime.
- It may record `AIRecommendationDiagnosticEvent` values.
- It may read the provider-availability snapshot for no-provider fallback
  decisions.
- It exposes `shouldBuildRecommendationContext` so the coordinator can skip
  expensive lexical and accepted-feedback snapshots after a lazy provider is
  known unavailable, while still building context for eager providers, injected
  providers, and lazy providers in the unknown/available states.
- It must not access host clients, marked text, candidate-panel presentation,
  Rime selection, commit/write paths, or settings persistence.

## Behavior Notes

- Scheduling starts with `InputAIRecommendationSchedulePolicy`; skipped states
  do not start provider tasks.
- The coordinator-provided provider availability gate is part of the runtime
  schedule context, so a lazy provider that is already known unavailable does
  not launch another request just because the lazy provider object exists.
- `hasKnownProvider` remains scoped to suppressing no-provider fallback rows; it
  is not the heavy-context construction gate.
- Provider requests never include real-time Rime candidate hints.
- Async results apply only when request id, generation, composition id, raw
  revision, and raw input still match the current composition snapshot.
- Reset and reschedule paths preserve existing `cancel_previous`, `cancelled`,
  `stale_result_dropped`, and `state_applied` diagnostic semantics.

## Tests

- `InputAIRecommendationRuntimeTests`
- `InputAIRecommendationSchedulePolicyTests`
- `InputControllerCoordinatorTests`
- `swift test`
