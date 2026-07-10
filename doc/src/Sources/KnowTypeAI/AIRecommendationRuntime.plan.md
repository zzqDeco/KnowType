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

## Tests

- `AIRecommendationRuntimeTests`
- `InputAIRecommendationRuntimeTests`
