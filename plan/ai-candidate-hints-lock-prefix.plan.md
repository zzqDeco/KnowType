# AI Candidate Hints And Locked Prefix Decoupling

## Summary

- Branch: `fix/ai-candidate-hints-lock-prefix`; PR base: `dev`.
- Unselected Rime candidates are no longer promoted into `lockedPrefix`.
- Current-page Rime candidates are sent to AI as contextual `candidateHints`.
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
- `InputControllerCoordinator` derives `candidateHints` from the active Rime
  page and schedules AI only when raw input plus confirmed prefix or hints
  provide enough context.
- `AIRecommendationRuntime` forwards `candidateHints` to providers and includes
  them in the recommendation cache key.
- With a `lockedPrefix`, runtime still sanitizes provider `text` as suffix-only
  and joins it after the locked prefix.
- Without a `lockedPrefix`, runtime treats provider `text` as the full
  commit-ready AI recommendation; hints are only model context.

## Test Plan

- `swift test --quiet`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`
- Unit tests cover hint propagation, cache invalidation when hints change, no
  first-candidate locked prefix during Rime composition, and full
  recommendation handling when no locked prefix exists.

## Assumptions

- `candidateHints` uses only the current Rime page and does not iterate the full
  candidate list.
- AI recommendations remain explicit: they update only the AI slot and are
  committed by existing AI actions.
- A future reasoning-effort setting can be handled separately if the local
  provider exposes it.
