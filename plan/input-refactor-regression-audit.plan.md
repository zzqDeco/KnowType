# Input Refactor Regression Audit

Status: Delivered

## Summary

This plan locks the input-method behavior after the coordinator extraction
sequence from PR #131 through PR #146. The audit baseline is
`afe116fa67569856479ee25ed55569e80195120e`, the parent of
`8ac7612 refactor(input-method): rename session suggestion pipeline`.

The goal is to verify that the runtime extractions did not change the user
visible key path, host write order, candidate-panel lifecycle, native Rime
commit behavior, or AI/lexical side-effect snapshots.

Audit result for this PR: the focused regression tests, targeted runtime suites,
full `swift test`, and diff review found no behavior drift requiring a fix.

## Scope

- Audit `Sources/KnowTypeInputMethod` and `Tests/KnowTypeInputMethodTests`
  against the fixed baseline.
- Add regression coverage for the coordinator-level paths that span multiple
  extracted runtimes.
- Do not continue splitting `InputControllerCoordinator` in this slice.
- Do not run install, repair, uninstall, or other commands that mutate local
  macOS input-source state.

## Implementation

- Add `InputControllerCoordinatorRefactorRegressionTests` in the coordinator
  test file so the new tests can reuse existing fake host, fake client, fake
  conversion engine, and recorder fixtures without widening their visibility.
- Lock standard inline host behavior: raw `n i`, attributed marked text,
  visible candidate panel, Space clear-before-insert, and composition reset.
- Lock terminal-style behavior: idle ASCII passthrough remains unwritten by
  KnowType, while explicit Chinese mode uses attributed placeholder marked text
  and candidate-panel preedit before Space commit.
- Lock lifecycle behavior around deactivate, close, native-ended, and delayed
  re-anchor so reset-before/after ordering stays observable through writes,
  panel hides, conversion-engine reset counts, and AI typing-context events.
- Record the audit commands and outcome in this plan; fix only verified behavior
  drift discovered by the tests or diff review.

## Test Plan

- `git diff --stat afe116fa67569856479ee25ed55569e80195120e..dev -- Sources/KnowTypeInputMethod Tests/KnowTypeInputMethodTests`
- `git diff --word-diff afe116fa67569856479ee25ed55569e80195120e..dev -- Sources/KnowTypeInputMethod/InputControllerCoordinator.swift`
- `rg -n "insertText|setMarkedText|clearMarkedText|finishLifecycle|compositionEnded|reset\\(|hideCandidatePanel|publishRuntimeEvent" Sources/KnowTypeInputMethod`
- `swift test --quiet --filter InputControllerCoordinatorRefactorRegressionTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputClientCompositionWriterTests`
- `swift test --quiet --filter InputCompositionLifecycleRuntimeTests`
- `swift test --quiet --filter InputCommitApplicationRuntimeTests`
- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter InputNativeCandidateNavigationRuntimeTests`
- `swift test --quiet --filter InputAIRecommendationRuntimeTests`
- `swift test --quiet --filter InputAIAcceptanceRuntimeTests`
- `swift test --quiet --filter InputLexicalCommitRuntimeTests`
- `swift test --quiet --filter InputSuggestionStateRuntimeTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- The baseline commit represents the stable host-carrier behavior before the
  coordinator runtime extraction sequence began.
- `InputEventBus` remains private; this audit observes lifecycle ordering
  through host writes, panel hides, conversion reset counts, and AI context
  recorder side effects instead of adding a production test seam.
- Any large behavior drift found later should get a dedicated fix PR after a
  failing regression test is committed.
