# InputTurnSequenceValidator

## Responsibility

`InputTurnSequenceValidator` validates the ordering of value-only
`InputTurnEffectSequence` plans before the coordinator executes IMK/AppKit/Rime
side effects.

## Boundaries

- It returns privacy-safe violation metadata only; it never executes effects.
- It must not inspect user text, candidate text, provider output, host clients,
  Rime sessions, or AppKit windows.
- `InputTurnSequencingRuntime` remains the owner of sequence construction.
- `InputControllerCoordinator` remains the owner of real side-effect execution.

## Behavior Notes

- Validation enforces the mature-IME-style event loop shape: commit side effects
  before insertion, post-insert verification after insertion, panel hide before
  lifecycle reset, native raw sync after native insertion, and direct passthrough
  without clearing stale host marked text.
- Violations include turn id, turn kind, composition id, raw revision, effect
  index, and effect name. They intentionally exclude committed text and raw input.
- `KNOWTYPE_TURN_DEBUG=1` logs the planned effect names and validation result
  for turn replay without recording user content.

## Tests

- `InputTurnSequenceValidatorTests`
- `InputTurnSequencingRuntimeTests`
- `InputControllerCoordinatorTests`
