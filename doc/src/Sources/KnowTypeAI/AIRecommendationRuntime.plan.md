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
- Registry generation changes fence the old runtime operation. A provider that
  ignores cancellation can finish, but its result is `.stale` and is dropped
  before candidate UI publication.

## Tests

- `AIRecommendationRuntimeTests`
- `InputAIRecommendationRuntimeTests`
- `ProviderRuntimeRegistryTests`
