# AIRecommendationRuntime.swift

## Responsibility

- Own recommendation request budgeting, payload single-flight, response
  sanitization, caching, and caller-visible hard timeout behavior.

## Boundaries

- Provider concurrency, generation fencing, and cooldown ownership remain in
  `ProviderRequestGate`; input-method publication remains outside this file.

## Behavior Notes

- `Defaults.debounceMilliseconds` is `0` so the provider runtime does not add a
  second 350 ms sleep after `InputAIRecommendationRuntime`'s 450 ms input-method
  debounce; callers that want standalone provider-layer debounce can still pass
  an explicit `debounceMilliseconds`.
- The single-flight owner uses the gate's hard-timeout execution seam. Waiters
  share that attempt and cannot multiply timeout failures.
- When all waiters for an in-flight payload fingerprint are cancelled, the
  shared attempt task is cancelled and tracked before resuming the final
  waiter, and any tracked cancelling attempt is drained after a cache miss
  (before gate admission/dispatch) so a cancelled composition session releases
  its `ProviderRequestGate` lease without blocking cache hits.
- The shared attempt task owns `AIHealthMonitor` observation, so one physical
  provider success or qualifying failure is observed once; waiters only consume
  the shared result.
- A hard timeout returns to recommendation callers immediately while a
  cancellation-resistant transport keeps its gate lease until actual
  completion.
- The runtime performs a value-only gate preflight before ENV, correction, or
  optional context projection. Persistence-blocked returns
  `AI 状态异常，正在重试` without document reads; later requests recheck the shared
  gate, whose deadline keeps those checks disk-free until recovery is due.

## Tests

- `AIRecommendationRuntimeTests` covers zero default provider debounce,
  in-flight task cancellation releasing `ProviderRequestGate` for the next
  session, shared-payload timeout ownership, lease retention through
  cancellation-resistant completion, repeated blocked preflights, and
  same-instance persistence recovery.
