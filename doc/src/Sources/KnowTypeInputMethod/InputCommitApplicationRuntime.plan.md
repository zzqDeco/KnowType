# InputCommitApplicationRuntime

## Responsibility

- Maps `InputCommitResult` values into commit-application plans for the
  coordinator.
- Builds accepted-feedback, AI acceptance, and lexical commit contexts from a
  captured `InputCompositionStateSnapshot`.

## Boundaries

- Must not call `insertText`, `setMarkedText`, Rime conversion, candidate-panel
  publication, AI runtimes, lexical runtimes, or task supervisors.
- Must not read host state directly. The coordinator supplies schema id, app
  bundle id, selected candidate source, prefix source, client, and composition
  snapshot facts.
- Must not own commit precedence. Space, Tab, numeric selection, and native
  candidate selection remain in the coordinator and commit policy.

## Behavior Notes

- `noAction` consumes only while composition is active, matching
  `InputCommitResultPolicy`.
- Commit side-effect contexts read raw input, composition id, and delete count
  from the snapshot captured before lifecycle reset.
- Composition lifecycle begin/finish planning belongs to
  `InputCompositionLifecycleRuntime`.

## Tests

- `InputCommitApplicationRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputAIAcceptanceRuntimeTests`
- `InputLexicalCommitRuntimeTests`
- `InputCompositionStateRuntimeTests`
