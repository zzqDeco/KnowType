# AI Recommendation Stability And Latency

## Status

Delivered

## Summary

Stabilize real-time AI recommendation requests without changing the configured
model, provider prompt, local proxy, Rime conversion, candidate ranking, host
compatibility, or Settings UI.

Current measurements show the local proxy and `gpt-5.3-codex-spark` provider
path are basically healthy: short requests are about 1.2 seconds median, and
KnowType-shaped requests are about 2.3 seconds median with occasional slower
responses. The input-method failure mode is repeated cancellation while the
user is still typing, which can make the proxy surface client-aborted requests
as short-lived 500s.

## Implementation

- `InputAIRecommendationRuntime` owns an IMK-side trailing debounce before
  provider transport dispatch. The default is 850 ms.
- During the debounce window the runtime keeps `.idle`, so the candidate panel
  does not flash a pending AI row while raw input is still changing.
- New input cancels only the pre-dispatch debounce task. Once provider transport
  has started, new input invalidates the old request id/generation and lets the
  old result return through the existing stale-drop checks.
- The input-method controller constructs `LazyDefaultAIRecommendationRuntime`
  with provider-layer debounce disabled, avoiding a second 350 ms wait after the
  IMK-side debounce.
- Privacy-safe AI diagnostics now include dispatch and transport stages:
  `dispatch_deferred`, `dispatch_cancelled_by_new_input`, `transport_started`,
  and `transport_left_stale`.

## Validation

- `InputAIRecommendationRuntimeTests` cover pre-dispatch cancellation, non-
  aborting started transport, pending publication after dispatch, stale result
  dropping, and no-heavy-context gates.
- `AIRecommendationRuntimeTests` keep the direct provider runtime default
  debounce at 350 ms and cover the input-method factory path with debounce 0.
- `InputHotPathPerformanceTests` guard the input-method path against accidental
  reintroduction of provider-layer debounce and transport-cancel coupling.

## Non-Goals

- No model switch.
- No proxy or provider API change.
- No prompt, candidate ordering, Rime, host compatibility, Settings UI, or
  installation script change.
