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
- Provider-backed continuation uses the secret-only cloud AI gate; host app
  identity such as Terminal, iTerm, or Xcode is not by itself a real-time AI
  disabled condition.
- Host state should be represented in testable value types before it reaches
  core or session logic.

## Tests

- `InputControllerCoordinatorTests`
- `MVPAcceptanceTests`
