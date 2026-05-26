# KnowType AI Remove Candidate Hints Bias

Status: Active

## Summary

- Branch: `fix/ai-remove-candidate-hints-bias`; PR base: `dev`.
- Real-time AI continuation must not receive current-page Rime candidates,
  highlighted-candidate state, or first-candidate ordering.
- `LEXICAL_PROFILE.md` remains the user lexical/tone profile, but it must be
  based on persisted userdb terms, recent commits, and selection history rather
  than the current composition's unconfirmed candidate page.

## Key Changes

- `InputControllerCoordinator` schedules AI from `rawInput` and optional
  confirmed `lockedPrefix`; it sends empty `candidateHints` and gates unconfirmed
  input by raw-input length.
- `AIRecommendationRuntime` clears legacy `candidateHints` before provider
  calls, cache-key generation, and eligibility checks.
- Continuation prompts and structured-output descriptions no longer mention
  candidate hints, highlighted hints, or first-candidate behavior.
- Request-time lexical context no longer adds realtime Rime candidates; persisted
  Rime userdb terms, recent commits, selection history, and tone profile remain.

## Test Plan

- Unit tests cover empty provider `candidateHints`, no highlighted hint signal,
  cache stability across candidate changes, raw-input length gating, and lexical
  profiles excluding current-page Rime candidates.
- Regression checks:
  - `swift test --quiet`
  - `./scripts/smoke-inputmethod-install.sh`
  - `./scripts/perf-input-hotpath.sh`
  - `git diff --check`

## Assumptions

- `candidateHints` and `LLMCandidateHint` stay in public models for compatibility
  but are unused by realtime continuation.
- `rawInput` remains part of provider requests because AI still needs the current
  user input to generate a useful recommendation.
- Long-term Rime userdb terms are allowed in `LEXICAL_PROFILE.md`; current
  unselected candidates are not.
