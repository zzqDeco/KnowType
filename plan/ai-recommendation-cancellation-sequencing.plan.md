# AI Recommendation Cancellation Sequencing

## Summary

Restore sequenced cancellation for stale real-time AI recommendation transports.
The input-method path keeps the 450 ms trailing debounce and pending spinner row,
but new input, reset, deactivate, or close no longer lets an already-stale
provider request run to completion by design.

## Scope

- `InputAIRecommendationRuntime` cancels active provider tasks after transport
  starts when the request becomes stale.
- `AIRecommendationRuntime` treats task cancellation and URL-session
  cancellation as normal cancellation, not provider failure.
- AI diagnostics distinguish cancellation requested, new-input cancellation,
  stale result drops, provider errors, and hard timeouts without logging raw
  input, prompt/context bodies, candidate text, or provider output.

Non-goals:

- No AI prompt, model, provider profile, proxy, Rime, candidate ordering, host
  write, Settings UI, or installation-script change.
- No rollback of pending spinner rows or the 450 ms input-method debounce.

## Implementation

- Pre-dispatch `dispatchDeferred` tasks remain cheaply cancellable before the
  provider is called.
- Once `transportStarted`, a newer input turn records
  `transport_left_stale`, `transport_cancellation_requested`, and
  `transport_cancelled_by_new_input`, then cancels the active task
  best-effort.
- Reset, deactivate, and close record the stale/cancellation request and cancel
  the active task without showing `AI 暂不可用`.
- `AIRecommendationRuntime` returns `.idle` for `CancellationError` and
  `URLError(.cancelled)` / `NSURLErrorCancelled`; these paths do not update
  provider health or cooldown.
- Hard timeout and real provider/decode/HTTP failures keep existing failure and
  cooldown behavior.

## Test Plan

- `InputAIRecommendationRuntimeTests` cover debounce cancellation, started
  transport cancellation, stale non-application, reset/close cancellation, and
  pending placeholder behavior.
- `AIRecommendationRuntimeTests` cover `CancellationError` and
  `URLError(.cancelled)` as non-failure cancellation while preserving timeout and
  provider-error behavior.
- Run:
  - `swift test --quiet --filter InputAIRecommendationRuntimeTests`
  - `swift test --quiet --filter AIRecommendationRuntimeTests`
  - `swift test --quiet --filter InputControllerCoordinatorTests`
  - `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
  - `swift test --quiet --filter InputHotPathPerformanceTests`
  - `swift test`
  - `git diff --check`

## Assumptions

- HTTP cancellation is best-effort; a provider may already have consumed some
  tokens, but KnowType should no longer intentionally await stale transports.
- Cancellation is an ordinary input sequencing outcome and must not mark the
  provider unavailable.
