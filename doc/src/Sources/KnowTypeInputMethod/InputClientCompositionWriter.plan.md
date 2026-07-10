# InputClientCompositionWriter

## Responsibility

`InputClientCompositionWriter` owns the host-facing composition write state
between `InputControllerCoordinator` and the low-level
`InputClientWriteCoordinator`.

## Boundaries

- It selects the effective write mode through `InputClientCompatibilityPolicy`.
- It decides idle half-width printable passthrough for ASCII/disabled modes;
  the coordinator handles full-width transformation before this boundary.
- It writes inline attributed preedit or commit-only attributed placeholder
  marked text.
- It tracks the KnowType-owned marked-text client id and clears only owned
  marked text before commit or lifecycle cleanup.
- It exposes commit-only preedit display text for the candidate panel.
- It does not own key handling, Rime snapshots, candidate ordering, AI
  recommendation state, panel anchoring, or lifecycle timing.

## Behavior Notes

- `InputClientCompositionWriteState` carries composition id, raw length, input
  mode state, and active-composition state. It intentionally does not store raw
  user text.
- Inline hosts receive attributed composition text through `setMarkedText`.
- Commit-only hosts receive a U+3000 attributed placeholder through
  `setMarkedText`; the real preedit is returned for candidate-panel display.
- All replacement ranges still come from `InputClientWriteCoordinator` and use
  `{NSNotFound, NSNotFound}`.
- Direct insert clears KnowType-owned marked text first unless the caller marks
  the write as an idle passthrough insertion.

## Tests

- `InputClientCompositionWriterTests`
- `InputControllerCoordinatorTests`
- `InputClientCompatibilityPolicyTests`
