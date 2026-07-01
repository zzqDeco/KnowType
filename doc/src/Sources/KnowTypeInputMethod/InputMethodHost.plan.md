# InputMethodHost

## Responsibility

`InputMethodHost` contains the AppKit/InputMethodKit server bootstrap seam for
the local input-method bundle.

## Boundaries

- Suggestion generation belongs to `SessionSuggestionPipeline`.
- Product correction and privacy rules stay in `KnowTypeCore`.
- Concrete IMK callback handling stays in `InputController` and
  `InputControllerCoordinator`.

## Behavior Notes

- `KnowTypeIMKServerBootstrap` wraps IMK server creation behind a tiny type so
  AppKit/InputMethodKit imports stay isolated.
- This file should not grow input behavior, host policy, candidate state, or AI
  runtime logic.

## Tests

- `swift build`
