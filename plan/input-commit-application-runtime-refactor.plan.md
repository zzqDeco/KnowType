# Input Commit Application Runtime Refactor

## Summary

- Extract commit-result planning, commit side-effect context construction, and
  lifecycle finish planning from `InputControllerCoordinator`.
- Keep the change refactor-only: the coordinator remains responsible for all
  order-sensitive IMK, Rime, candidate-panel, AI, lexical, and lifecycle side
  effects.

## Scope

- Add `InputCommitApplicationRuntime` under `Sources/KnowTypeInputMethod`.
- Move value-only mapping and context construction out of the coordinator.
- Keep host writes, marked-text cleanup, Rime conversion/reset,
  candidate-panel publication, AI/lexical runtime calls, input-mode policy, and
  install tooling in existing owners.

## Implementation

- Runtime maps `InputCommitResult` into insert, polish, keep, or no-action
  plans using the existing commit-result policy.
- Runtime constructs accepted-feedback, AI acceptance, and lexical commit
  contexts from a captured composition snapshot plus coordinator-supplied
  schema, app, candidate-source, and client facts.
- Runtime constructs lifecycle finish plans from explicit reason fields instead
  of depending on private lifecycle reason enums.
- Coordinator consumes the returned plans and contexts while preserving the
  previous side-effect order.

## Test Plan

- `swift test --quiet --filter InputCommitApplicationRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputAIAcceptanceRuntimeTests`
- `swift test --quiet --filter InputLexicalCommitRuntimeTests`
- `swift test --quiet --filter InputCompositionStateRuntimeTests`
- `swift test --quiet --filter InputClientCompositionWriterTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is a refactor-only PR.
- Commit precedence, host carrier behavior, AI recommendation, Rime schema,
  Settings UI, install scripts, and provider prompts remain unchanged.
- A later PR can split more lifecycle or write orchestration only after this
  plan/context boundary is stable.
