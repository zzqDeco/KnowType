# KnowType Input Method First-Key Review Follow-up

## Summary

- Status: Active.
- Branch: `fix/input-first-key-review-followup`.
- Goal: resolve the PR #150 review regressions without adding a new
  performance architecture or changing input behavior.

## Scope

- Split host scheduling so delayed re-anchor remains candidate-panel only,
  while post-insert AI feedback caret verification runs on the next main-queue
  turn.
- Gate heavy AI recommendation context construction on provider availability
  semantics that distinguish unknown/available providers from known-unavailable
  lazy providers.
- Keep native Rime prewarm best-effort by removing global session-creation
  serialization that can make a quick first key wait behind speculative prewarm.

## Non-Goals

- Do not change Rime schemas, candidate ranking, host compatibility policy,
  AI prompts, provider outputs, Settings UI, or install/repair scripts.
- Do not continue broader coordinator/runtime decomposition in this follow-up.

## Verification

- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputAIRecommendationRuntimeTests`
- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter RimeConversionEngineTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `KNOWTYPE_STRICT_INPUT_PERF=1 swift test --quiet --filter InputHotPathPerformanceTests/testStrictRimeOnlyHotPathBudgetsWhenEnabled`
- `swift test`
- `git diff --check`
