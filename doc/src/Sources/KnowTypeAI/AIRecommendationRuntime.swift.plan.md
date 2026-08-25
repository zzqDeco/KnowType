# AIRecommendationRuntime.swift

## Responsibility

- Own recommendation request budgeting, payload single-flight, response
  sanitization, caching, and caller-visible hard timeout behavior.

## Boundaries

- Provider concurrency, generation fencing, and cooldown ownership remain in
  `ProviderRequestGate`; input-method publication remains outside this file.

## Behavior Notes

- The single-flight owner uses the gate's hard-timeout execution seam. Waiters
  share that attempt and cannot multiply timeout failures.
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

- `AIRecommendationRuntimeTests` covers shared-payload timeout ownership and
  lease retention through cancellation-resistant completion, plus
  repeated blocked preflights and same-instance persistence recovery.
