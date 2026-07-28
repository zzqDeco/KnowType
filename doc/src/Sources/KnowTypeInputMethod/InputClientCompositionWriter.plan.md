# InputClientCompositionWriter

## Responsibility

`InputClientCompositionWriter` owns the host-facing composition write state
between `InputControllerCoordinator` and the low-level
`InputClientWriteCoordinator`.

## Boundaries

- It selects the effective write mode through `InputClientCompatibilityPolicy`.
- It decides idle printable passthrough for ASCII/disabled modes. The
  coordinator handles full-width transformation before this boundary only when
  a usable client is present; missing clients remain unhandled in every width.
- It writes inline attributed preedit or commit-only attributed placeholder
  marked text.
- It tracks KnowType-owned marked text by client id and composition id, and
  clears only that exact ownership before commit or lifecycle cleanup.
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
- Symbol presentation returns a structured inline/placeholder result to the
  coordinator. It uses the same carrier path as text composition without
  storing the selected symbol.
- All replacement ranges still come from `InputClientWriteCoordinator` and use
  `{NSNotFound, NSNotFound}`.
- Direct insert clears KnowType-owned marked text first unless the caller marks
  the write as an idle passthrough insertion.
- Missing or changed clients can release stale local ownership without sending
  a marked-text write to another host. An older composition id cannot clear a
  newer mark on the same client.

## Tests

- `InputClientCompositionWriterTests`
- `InputControllerCoordinatorTests`
- `InputClientCompatibilityPolicyTests`
