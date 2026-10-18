# AI Recommendation Cancellation Sequencing

Status: Delivered

## Summary

Restore sequenced cancellation for stale real-time AI recommendation transports.
The input-method path keeps the 450 ms trailing debounce and pending spinner row,
but new input, reset, deactivate, or close no longer lets an already-stale
provider request run to completion by design.

## Scope

- `InputAIRecommendationRuntime` keeps an in-flight transport during
  mid-composition input changes (`reason == "input_changed"` with non-empty
  input) and coalesces newer keystrokes into `trailingWork`, while explicit
  session reset, commit, Escape, deactivate, or close cancels both deferred and
  in-flight transport tasks immediately.
- `dispatchTrailingIfNeeded()` routes trailing work through `startDeferred` so
  trailing requests still wait for the 450 ms input-method debounce window.
- `AIRecommendationRuntime` defaults `debounceMilliseconds` to `0` (avoiding a
  second 350 ms debounce layer), propagates task cancellation to in-flight
  provider attempt tasks when all waiters cancel so `ProviderRequestGate` is
  released immediately, and treats task/URL cancellation as normal cancellation
  rather than provider failure.
- AI diagnostics distinguish cancellation, stale result drops, provider errors,
  and hard timeouts without logging raw input, prompt/context bodies, candidate
  text, or provider output.

Non-goals:

- No AI prompt, model, provider profile, proxy, Rime, candidate ordering, host
  write, Settings UI, or installation-script change.
- No rollback of pending spinner rows or the 450 ms input-method debounce.

## Implementation

- Pre-dispatch `dispatchDeferred` tasks remain cheaply cancellable before the
  provider is called.
- During active composition typing, an already-started transport records
  `transport_left_stale` and queues the latest revision in `trailingWork`; when
  the active transport finishes, `dispatchTrailingIfNeeded()` starts a fresh
  debounce window via `startDeferred`.
- Session reset, commit, Escape, deactivate, and close record `cancel_previous`
  and `transport_left_stale`, cancel `transportTask`, clear `activeWork` and
  `trailingWork`, and release the single-flight slot without showing
  `AI 暂不可用`.
- `AIRecommendationRuntime` registers cancellation tracking and cancels its
  in-flight attempt task before resuming the final cancelled waiter, and drains
  any tracked cancelling attempt after a cache miss (before gate
  admission/dispatch), returning `.idle` for `CancellationError` and
  `URLError(.cancelled)` / `NSURLErrorCancelled` without updating provider
  health or cooldown.
- Hard timeout and real provider/decode/HTTP failures keep existing failure and
  cooldown behavior, and `doc/architecture.plan.md` / `doc/interfaces.plan.md`
  record the updated cancellation and debounce contracts.

## Validation

Manual validation on the merged `dev` build with `KNOWTYPE_AI_DEBUG=1` and
`KNOWTYPE_PERF_DEBUG=1` confirmed the cancellation path without provider-health
poisoning:

- `transport_started=5`
- `transport_cancellation_requested=5`
- `transport_cancelled_by_new_input=4`
- `provider_error=0`, `timeout=0`, `unavailable=0`

The remaining started transport was invalidated by composition lifecycle
cleanup, not continued input. The debug log also showed debounce-stage
cancellations before provider dispatch, which avoid unnecessary provider calls.

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
