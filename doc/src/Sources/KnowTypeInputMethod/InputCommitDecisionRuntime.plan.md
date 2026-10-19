# InputCommitDecisionRuntime

`InputCommitDecisionRuntime` owns pure commit decision planning for the IMK
coordinator.

Responsibilities:

- map `Space`, `Tab`, `Option-number`, raw commit, selected candidate, AI slot,
  current suggestion, and composition-buffer facts into executable decision
  plans through action-specific helpers (`decideReturn`, `decideSpace`,
  `decideTab`, `decideOptionNumber`)
- isolate legacy `CompositionBuffer` segment checks into guard-first private
  helpers (`resolveLegacySegmentedReturnDecisionIfNeeded`,
  `resolveLegacySegmentedSpaceDecisionIfNeeded`,
  `resolveLegacySegmentedTabDecisionIfNeeded`) that return `nil` immediately on
  the Rime-only hot path (`!context.compositionBuffer.hasResolvedSegments`)
- preserve Rime/native priority by returning plans such as native Space,
  native candidate selection, segment application, or ordinary commit result
- decide accepted-AI candidate identity and prefix-learning candidate text
  without recording learning side effects

Boundaries:

- It does not call Rime, host clients, candidate-panel presenters, AI
  providers, lexical runtimes, or marked-text writers.
- `InputControllerCoordinator` executes all returned plans and keeps
  order-sensitive side effects: Rime `process`, segment mutation, host insert,
  lifecycle reset, panel publication, AI acceptance, and lexical recording.
- `InputCommitApplicationRuntime` still owns mapping a chosen
  `InputCommitResult` to insert/no-action application and side-effect contexts.
- Stateless value-in/value-out type invoked synchronously on the coordinator's
  main-thread turn path.

Tests:

- `InputCommitDecisionRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputControllerCoordinatorRefactorRegressionTests`
