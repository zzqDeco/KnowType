# PrefixContinuationEngine

## Responsibility

`PrefixContinuationEngine` owns continuation generation after a prefix has been
locked.

## Boundaries

- It may sanitize provider output, but it must not rewrite the locked prefix.
- Explicit polish is the only default path that may request rewriting existing
  text.
- Provider protocol details stay in `KnowTypeProviders`.

## Behavior Notes

- Continuation prompts ask for continuation text only.
- Provider output is still sanitized because providers can return full
  sentences or repeat the prefix.
- `sanitizeContinuationDetailed` reports normalized rejection and repair
  reasons such as `same_as_prefix`, `still_repeats_prefix`,
  `no_usable_suffix`, and `repeated_prefix_repaired` for AI diagnostics.
- When no provider is configured, local fallback continuation may be used.
- When a provider is configured but fails or returns unusable output,
  continuation rows stay empty instead of showing mock AI text.
- Level 0 input clears continuation candidates.

## Tests

- `PrefixContinuationEngineTests`
- `InputSessionControllerTests`
- Provider failure and fallback tests in input-method coverage
