# InputMethodHost

## Responsibility

`InputMethodHost` contains host-facing types used by the input-method package to
model app context and runtime integration.

## Boundaries

- Product correction and privacy rules stay in `KnowTypeCore`.
- Concrete IMK callback handling stays in `InputController` and
  `InputControllerCoordinator`.

## Behavior Notes

- Host app bundle identifiers help apply protected app policy and input-mode
  defaults.
- Host state should be represented in testable value types before it reaches
  core or session logic.

## Tests

- `InputControllerCoordinatorTests`
- `MVPAcceptanceTests`
