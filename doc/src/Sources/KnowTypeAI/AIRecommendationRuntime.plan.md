# AIRecommendationRuntime

## Responsibility

`AIRecommendationRuntime` owns real-time provider dispatch, response-state
construction, cache interaction, health reporting, and the final
`AIRecommendationCandidate` presented to input-method callers.

## Boundaries

- `PrefixContinuationEngine` in `KnowTypeCore` owns locked-prefix response
  sanitization and repair.
- Provider-specific request and response formats stay in `KnowTypeProviders`.
- The runtime must not rewrite a confirmed locked prefix while constructing
  display text.

## Behavior Notes

- When a request has a locked prefix, every provider candidate passes through
  `sanitizeContinuationDetailed`; rejected candidates do not reach ready state.
- The original locked prefix is retained as `prefixText`. The sanitized suffix
  becomes `continuationText`, and their join becomes `displayText`.
- Repaired suffix punctuation from `PrefixContinuationEngine` is preserved in
  final display text, including Chinese and English comma, period, semicolon,
  and colon. A single exact duplicate at the prefix boundary stays removed.
- Sanitizer repair and rejection reasons are emitted through privacy-safe AI
  diagnostics without logging candidate text.
- `LazyDefaultAIRecommendationRuntime` obtains a registry lease only after the
  request passes provider-dispatch eligibility. It caches one recommendation
  runtime per provider generation, so cache and health state do not cross a
  configuration change.
- The runtime validates UTF-8 budgets before dispatch: raw input and locked
  prefix are each at most 4 KiB, the recommendation logical payload is at most
  32 KiB, and the adapter HTTP body is at most 64 KiB. Local budget rejection is
  not a provider failure.
- Cache keys use the actual budgeted request payload fingerprint. The shared
  `ProviderRequestGate` enforces one in-flight request per hashed provider
  identity and applies generation fencing and bounded cooldowns.
- `Defaults.debounceMilliseconds` is `0` so the provider runtime does not add a
  second 350 ms sleep after `InputAIRecommendationRuntime`'s 450 ms input-method
  debounce; callers that want standalone provider-layer debounce can still pass
  an explicit `debounceMilliseconds`.
- When an individual waiter for an in-flight payload fingerprint is cancelled,
  that caller unblocks immediately with `.idle` while any surviving waiter keeps
  the shared attempt alive; when all waiters are cancelled, the shared attempt
  task is cancelled immediately and tracked per `(requestGate, providerIdentity)`
  until its `ProviderRequestGate` lease unwinds, preventing a cancelled
  composition session from holding the same provider's gate busy until hard
  timeout without delaying other providers sharing the gate.
- The shared payload task owns provider-health observation for its physical
  attempt: it records one successful result or one qualifying failure. Awaiting
  callers only consume that result and do not repeat health observation or
  create another gate attempt; local budget, cancellation, gate admission, and
  persistence branches remain non-health outcomes.
- Registry generation changes fence the old runtime operation. A provider that
  ignores cancellation can finish, but its result is `.stale` and is dropped
  before candidate UI publication.

## Tests

- `AIRecommendationRuntimeTests`
- `InputAIRecommendationRuntimeTests`
- `ProviderRuntimeRegistryTests`
