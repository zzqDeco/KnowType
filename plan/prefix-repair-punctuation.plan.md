# Prefix Repair Punctuation

## Status

Active

## Summary

- Branch: `fix/prefix-repair-punctuation`; PR base: `dev`; issue: `#181`.
- Preserve necessary punctuation when repairing provider responses that repeat
  a confirmed locked prefix.
- Keep the repair inside the Core sanitizer so direct continuation and AI
  runtime callers share the same strict prefix-lock behavior.

## Scope

- Update `PrefixContinuationEngine.sanitizeContinuationDetailed` repeated-prefix
  repair.
- Cover Core sanitizer results and production AI recommendation display text.
- Document the Core sanitizer and AI runtime ownership boundary.
- Do not change prompts, provider adapters, response schemas, candidate joining,
  input-method shortcuts, or fallback selection.

## Implementation

- Remove only the exact normalized locked prefix from a repeated-prefix provider
  response.
- Trim whitespace and the explicit visual protocol separators `|` and `｜` from
  the repaired suffix. Do not trim Chinese or English comma, period, semicolon,
  or colon.
- If the normalized locked prefix ends with the same supported punctuation that
  begins the suffix, remove exactly that one duplicate character.
- Preserve already suffix-only results and reject empty separator-only repairs.
- Keep a validation-only boundary scan so punctuation cannot hide a second
  repeated locked prefix.

## Test Plan

- `swift test --filter PrefixContinuationEngineTests`
- `swift test --filter AIRecommendationRuntimeTests`
- `swift test`
- `git diff --check`
- Fixtures cover English comma, Chinese comma, periods, semicolons, colons,
  exact duplicate punctuation, pure visual separators, normal suffix-only
  output, and final display text.

## Assumptions

- Duplicate removal is limited to `,`, `，`, `.`, `。`, `;`, `；`, `:`, and `：`.
- `|` and `｜` are protocol presentation separators, not suffix punctuation.
- The original locked-prefix bytes remain authoritative in the AI candidate and
  final display text.
