# Input Commit Decision Runtime Refactor

Status: Active

## Summary

Extract the remaining pure commit decision logic from
`InputControllerCoordinator` into `InputCommitDecisionRuntime`.

The runtime returns value-only plans for commit actions and selected candidates.
The coordinator still executes all side effects: Rime processing, segment
mutation, host insertion, marked-text cleanup, candidate-panel publication,
AI acceptance, lexical recording, and lifecycle reset.

## Implementation Notes

- Add `InputCommitDecisionRuntime` with context and plan value types for
  direct passthrough, empty raw commit finish, native Space processing, native
  candidate selection, segment application, and ordinary `InputCommitResult`.
- Move pure rules for Tab suppression, AI shortcut priority, fully resolved
  composition commits, selected candidate priority, number selection,
  accepted-AI identity, and prefix-learning target selection out of the
  coordinator.
- Keep `InputCommitApplicationRuntime` focused on applying an already chosen
  `InputCommitResult`; it does not decide which candidate/action wins.
- Keep Rime and host/client writes in `InputControllerCoordinator`.

## Validation

- `swift test --quiet --filter InputCommitDecisionRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputControllerCoordinatorRefactorRegressionTests`
- `swift test --quiet --filter InputCommitApplicationRuntimeTests`
- `swift test --quiet --filter InputNativeCandidateNavigationRuntimeTests`
- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter InputAIAcceptanceRuntimeTests`
- `swift test --quiet --filter InputLexicalCommitRuntimeTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Acceptance

- User-visible key behavior remains unchanged for Space, Tab, Option-number,
  Return, numeric candidate selection, Rime/native candidate priority, and AI
  acceptance.
- The new runtime can be tested without host clients, Rime engine instances,
  AppKit candidate-panel presenters, AI providers, or event buses.
