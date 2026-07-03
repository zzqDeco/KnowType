# Input Turn Sequence Hardening

## Summary

- Make the input turn ordering rules explicit and testable after the v0.2.3
  runtime refactor sequence.
- Keep `InputControllerCoordinator` as the single executor of IMK/AppKit/Rime
  side effects while adding privacy-safe diagnostics for turn replay.

## Scope

- Add a value-only `InputTurnSequenceValidator`.
- Add `KNOWTYPE_TURN_DEBUG=1` turn sequence diagnostics.
- Update turn sequencing tests and source notes.
- Do not add a new effect executor, move host writes, change candidate ranking,
  change Rime behavior, or change user-visible input behavior.

## Implementation

- Validate commit, lifecycle, native, and direct-passthrough effect ordering with
  privacy-safe violation records.
- Trace turn id, kind, composition id, raw revision, raw length, handled state,
  current panel generation, effect names, and validation result when turn debug
  is enabled or validation finds a violation.
- Keep all real side effects in `InputControllerCoordinator.executeTurnEffectSequence`.

## Test Plan

- `swift test --quiet --filter InputTurnSequenceValidatorTests`
- `swift test --quiet --filter InputTurnSequencingRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputControllerCoordinatorRefactorRegressionTests`
- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

## Assumptions

- Mature IME alignment means central event-loop execution plus explicit value
  sequencing, not a second executor abstraction.
- Debug logs must remain privacy-safe and omit user input, candidate text, and
  provider content.
