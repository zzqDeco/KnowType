# InputTurnSequencingRuntime

`InputTurnSequencingRuntime` owns value-only sequencing for a single input turn.

Responsibilities:

- issue monotonic `InputTurnToken` values for commit, native conversion,
  lifecycle finish, and direct passthrough turns
- return ordered `InputTurnEffectSequence` values for commit insert/reset,
  native commit-with-still-composition, native handled refresh, lifecycle
  finish, and idle passthrough
- preserve pre-reset composition snapshots in sequence tokens so commit and
  lifecycle side-effect contexts are built from the intended input turn

Boundaries:

- It does not call host clients, Rime, candidate-panel presenters, marked-text
  writers, AI runtimes, lexical runtimes, or event buses.
- `InputControllerCoordinator` remains the executor for all returned effects.
- `InputCommitDecisionRuntime` decides which action wins; this runtime only
  sequences effects after a decision is already known.
- `InputCandidatePanelPublicationRuntime` remains the owner of candidate-panel
  frame generations and stale async publication gates.

Tests:

- `InputTurnSequencingRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputControllerCoordinatorRefactorRegressionTests`
