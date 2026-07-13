# PrefixContinuationEngine

## Responsibility

`PrefixContinuationEngine` owns continuation generation after a prefix has been
locked.

## Boundaries

- It may sanitize provider output, but it must not rewrite the locked prefix.
- No input action may request rewriting existing locked-prefix text.
- Provider protocol details stay in `KnowTypeProviders`.

## Behavior Notes

- Continuation prompts ask for continuation text only.
- Provider output is still sanitized because providers can return full
  sentences or repeat the prefix.
- Repeated-prefix repair removes the exact normalized prefix and trims only
  whitespace plus the explicit visual protocol separators `|` and `｜`.
  Chinese and English comma, period, semicolon, and colon remain part of the
  suffix.
- When the locked prefix already ends with the same boundary punctuation that
  begins the repaired suffix, exactly one duplicate punctuation character is
  removed. Different punctuation is preserved.
- Boundary punctuation is ignored only while checking whether a repaired
  suffix repeats the locked prefix again; it is not removed from accepted
  output. Ordinary suffix-only provider output remains unchanged.
- `sanitizeContinuationDetailed` reports normalized rejection and repair
  reasons such as `same_as_prefix`, `still_repeats_prefix`,
  `no_usable_suffix`, and `repeated_prefix_repaired` for AI diagnostics.
- When no provider is configured, local fallback continuation may be used.
- When a provider is configured but fails or returns unusable output,
  continuation rows stay empty instead of showing mock AI text.
- Provider-backed continuation is hard-blocked only by secret-like locked
  prefixes or raw input. Level 0 correction-protection input still clears local
  fallback continuation candidates when no provider is configured.

## Tests

- `PrefixContinuationEngineTests`
- `InputSessionControllerTests`
- Provider failure and fallback tests in input-method coverage
