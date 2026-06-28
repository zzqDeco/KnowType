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
- `CandidatePanelViewModel` carries optional `preeditDisplayText` for
  commit-only hosts where raw/preedit must be visible in the candidate panel
  rather than the host text field.
- Keeping actions typed lets input-method tests cover behavior without
  installing a Text Input Source.

## Tests

- `InputSessionControllerTests`
- `InputControllerCoordinatorTests`
- `InputKeyCommandMapperTests`
