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
- A hard timeout returns to recommendation callers immediately while a
  cancellation-resistant transport keeps its gate lease until actual
  completion.

## Tests

- `AIRecommendationRuntimeTests` covers shared-payload timeout ownership and
  lease retention through cancellation-resistant completion.
