# KnowType AI Trigger Stability Without Candidate Hints

Status: Active

## Summary

- Branch: `fix/ai-trigger-stability-no-hints`; PR base: `dev`.
- Keep real-time AI independent from current-page Rime candidates, highlighted
  candidate state, and first-candidate ordering.
- Make raw-input-only AI scheduling stable after candidate hints were removed:
  three visible raw characters are enough to trigger, while locked prefixes keep
  the stricter prefix-quality threshold.

## Key Changes

- Add `AIRecommendationTriggerPolicy` as the shared cloud-eligibility rule for
  `InputControllerCoordinator` and `AIRecommendationRuntime`.
- Gate no-locked-prefix requests at three visible raw characters; keep locked
  prefixes at two Han characters or six visible mixed/Latin characters.
- Increase the default AI recommendation debounce to 350 ms so continuous typing
  coalesces before provider requests.
- Keep `candidateHints` empty for real-time continuation and keep current-page
  Rime candidates out of request-time `LEXICAL_PROFILE.md`.
- Record `raw_too_short`, `waiting_for_idle`, and
  `debounce_cancelled_by_new_input` diagnostic reasons without logging raw text.

## Test Plan

- Unit tests cover three-character raw input triggers, one/two-character raw
  input skips, strict locked-prefix thresholds, debounce cancellation reasons,
  empty realtime candidate hints, and prompt text without first-candidate bias.
- Regression checks:
  - `swift test --quiet`
  - `./scripts/smoke-inputmethod-install.sh`
  - `./scripts/perf-input-hotpath.sh`
  - `git diff --check`

## Assumptions

- `candidateHints` and `LLMCandidateHint` remain as compatibility fields but are
  unused by real-time continuation.
- Three-character triggering applies only when there is no confirmed
  `lockedPrefix`; short confirmed prefixes should still avoid low-quality cloud
  continuation.
- This change does not alter Rime candidate ordering, model selection,
  candidate-panel UI, input-source registration, or release branches.
