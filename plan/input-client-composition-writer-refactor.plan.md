# Input Client Composition Writer Refactor

## Summary

Extract host composition write decisions from `InputControllerCoordinator` into
`InputClientCompositionWriter`.

This PR keeps IMK behavior unchanged while reducing coordinator ownership of
host write-mode selection, idle half-width ASCII passthrough, placeholder marked text, and
KnowType-owned marked-text cleanup.

## Scope

- Add `InputClientCompositionWriter` as the composition-write boundary above
  `InputClientWriteCoordinator`.
- Keep `InputClientCompatibilityPolicy` responsible for write-mode selection.
- Keep `InputClientWriteCoordinator` responsible for low-level `insertText`,
  `setMarkedText`, replacement range, and debug logging.
- Update `InputControllerCoordinator` to provide only current composition
  metadata and to schedule delayed re-anchors after marked text is written.
- Add focused tests for inline marked text, commit-only placeholder marked text,
  idle passthrough, and clear-before-insert ordering.

Non-goals:

- Do not change host compatibility defaults.
- Do not change Rime conversion, AI recommendation, candidate ordering,
  candidate panel layout, or install scripts.
- Do not split the AI scheduler or commit policy in this PR.

## Implementation

- Introduce `InputClientCompositionWriteState` with composition id, raw length,
  input mode state, and active-composition state. It intentionally carries no
  raw user text.
- Move owned marked-text tracking into `InputClientCompositionWriter`.
- Move commit-only placeholder construction into
  `InputClientCompositionWriter`.
- Route coordinator insertion and passthrough decisions through the new writer.
- Preserve `NSNotFound` replacement ranges through the existing
  `InputClientWriteCoordinator`.

## Test Plan

- `swift test --quiet --filter InputClientCompositionWriterTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputClientCompatibilityPolicyTests`
- `swift test`
- `git diff --check`

## Assumptions

- This is a boundary refactor only; host behavior should remain identical.
- The next coordinator split should target either commit-result policy or AI
  scheduling, after this write boundary has landed.
