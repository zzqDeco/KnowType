# InputModeStateMachine

## Responsibility

`InputModeStateMachine` is the pure value owner for Chinese/ASCII input,
Chinese/English punctuation, symbol width, punctuation source, and monotonic
mode generation.

## Boundaries

- It plans state transitions only and performs no IMK, AppKit, UserDefaults, or
  Rime side effects.
- Thread safety and process sharing belong to
  `ProcessInputModeStateRuntime`.
- Punctuation rendering belongs to `InputPunctuatorRuntime`.

## Behavior Notes

- Initial state is Chinese input, Chinese punctuation, configured global width,
  and `punctuationSource = linked`.
- Toggling text mode synchronizes punctuation to the destination mode and
  clears any manual override.
- Punctuation may be toggled only in Chinese mode and then uses source
  `manual`. The same event is a no-op in ASCII mode.
- Width transitions never alter text or punctuation.
- Generation increments only when state or punctuation source changes.

## Tests

- `InputModeStateMachineTests`
- `ProcessInputModeStateRuntimeTests`
- `InputControllerCoordinatorTests`
