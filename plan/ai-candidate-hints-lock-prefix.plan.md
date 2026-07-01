# AI Candidate Hints And Locked Prefix Decoupling

## Summary

- Branch: `fix/ai-candidate-hints-lock-prefix`; PR base: `dev`.
- Unselected Rime candidates are no longer promoted into `lockedPrefix`.
- Current-page Rime candidates were initially sent as contextual
  `candidateHints`; this behavior is superseded by
  `ai-remove-candidate-hints-bias.plan.md`, which keeps realtime continuation
  requests candidate-free.
- If no `lockedPrefix` exists, the provider returns a full commit-ready
  recommendation. It does not need to explicitly choose a base from hints.

## Scope

- Add `candidateHints` to `LLMRequest` and `AIRecommendationRequest`.
- Preserve `lockedPrefix` for user-confirmed or already resolved text only.
- Keep Rime key handling, candidate selection, and candidate panel visibility
  unchanged.
- Keep provider strict JSON schema shape as `text`, `confidence`, and `reason`;
  do not add a required `base` field.

## Implementation

- `RimeConversionEngine` native snapshots build `SuggestionResponse` without
  setting `lockedPrefix` from the first current-page candidate.
- `InputControllerCoordinator` no longer derives realtime `candidateHints`;
  AI scheduling uses raw input plus confirmed prefixes.
- `InputControllerCoordinator` forwards confirmed locked prefixes verbatim,
  including intentional whitespace, and trims only for blank-prefix checks.
- `AIRecommendationRuntime` keeps `candidateHints` as a compatibility field but
  clears it before provider requests and cache-key generation.
- With a `lockedPrefix`, runtime still sanitizes provider `text` as suffix-only
  and joins it after the original locked prefix, preserving intentional
  whitespace in the user-confirmed text.
- Without a `lockedPrefix`, runtime treats provider `text` as the full
  commit-ready AI recommendation; hints are only model context.
- If a non-empty `lockedPrefix` exists, cloud eligibility uses that prefix's
  length only; candidate hints cannot bypass the short-prefix gate.

## Test Plan

- `swift test --quiet`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`
- Unit tests cover empty realtime hints, no first-candidate locked prefix during
  Rime composition, and full
  recommendation handling when no locked prefix exists.
- Review hardening tests cover short locked-prefix gating and
  whitespace preservation in the final AI display text.

## Assumptions

- `candidateHints` remains in public models for compatibility but is not used by
  realtime continuation.
- AI recommendations remain explicit: they update only the AI slot and are
  committed by existing AI actions.
- A future reasoning-effort setting can be handled separately if the local
  provider exposes it.
