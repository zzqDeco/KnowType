# InputActions

## Responsibility

`InputActions` defines testable input intents and actions used by the session
and coordinator layers.

## Boundaries

- It should stay independent of AppKit event objects.
- Host-specific event translation belongs to `InputKeyCommandMapper` and the
  IMK controller boundary.

## Behavior Notes

- Actions cover composition input, cancel, delete, navigation, punctuation,
  numeric row selection, raw commit, continuation commit, and explicit polish.
- Keeping actions typed lets input-method tests cover behavior without
  installing a Text Input Source.

## Tests

- `InputSessionControllerTests`
- `InputControllerCoordinatorTests`
- `InputKeyCommandMapperTests`
