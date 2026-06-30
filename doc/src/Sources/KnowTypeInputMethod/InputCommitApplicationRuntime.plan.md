# InputCommitApplicationRuntime

## Responsibility

- Maps `InputCommitResult` values into commit-application plans for the
  coordinator.
- Builds accepted-feedback, AI acceptance, and lexical commit contexts from a
  captured `InputCompositionStateSnapshot`.
- Builds lifecycle finish plans that preserve the finishing composition id,
  optional commit text, panel visibility reason, and owned marked-text clear
  decision.

## Boundaries

- Must not call `insertText`, `setMarkedText`, Rime conversion, candidate-panel
  publication, AI runtimes, lexical runtimes, or task supervisors.
- Must not read host state directly. The coordinator supplies schema id, app
  bundle id, selected candidate source, prefix source, client, and composition
  snapshot facts.
- Must not own commit precedence. Space, Tab, numeric selection, native
  candidate selection, and polish decisions remain in the coordinator and
  commit policy.

## Behavior Notes

- `noAction` consumes only while composition is active, matching
  `InputCommitResultPolicy`.
- Commit side-effect contexts read raw input, composition id, and delete count
  from the snapshot captured before lifecycle reset.
- Lifecycle finish plans use explicit reason fields instead of depending on the
  private lifecycle-reason enum.

## Tests

- `InputCommitApplicationRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputAIAcceptanceRuntimeTests`
- `InputLexicalCommitRuntimeTests`
- `InputCompositionStateRuntimeTests`
