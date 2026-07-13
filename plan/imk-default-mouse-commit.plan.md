# Restore Default IMK Mouse Commit

## Summary

- Restore InputMethodKit's default behavior of committing an active composition
  when the user clicks outside its marked range.
- Keep the fix at the recognized-events registration boundary tracked by GitHub
  issue #176.

## Scope

- Return only the `NSEvent.EventTypeMask.keyDown` raw value from
  `KnowTypeInputController.recognizedEvents(_:)`.
- Add a small value-only policy and an exact regression test for the registered
  mask.
- Keep `InputKeyEventKind`, key-up mapping, and flags-changed mapping available
  for existing tests and seams. Do not change shortcut behavior or add custom
  mouse handling.
- Update the user-facing README behavior, IMK architecture, and controller
  source note.

## Implementation

- `InputControllerRecognizedEventPolicy` owns the raw IMK recognized-events
  value and returns only `keyDown`.
- `KnowTypeInputController.recognizedEvents(_:)` delegates to that policy, so
  registering another event requires changing the exact policy regression test.
- Modifier-sensitive shortcuts continue to use the modifier flags carried by
  key-down events.

## Test Plan

- Run `swift test --filter InputControllerRecognizedEventPolicyTests`.
- Run `swift test --filter InputKeyCommandMapperTests`.
- Run `swift test --filter InputCompositionLifecycleRuntimeTests`.
- Run `swift test --filter InputControllerCoordinatorTests`.
- Run the complete `swift test` suite and `git diff --check`.
- Installed manual acceptance in TextEdit, Chrome/Electron, and a code editor:
  start a marked composition, click at a caret position outside the marked
  range, confirm the composition commits and the candidate panel closes, then
  type again and confirm input begins at the new caret without stale text.
- Repeat `Option + /` and `Shift + Space` in the installed build to confirm their
  key-down modifier semantics are unchanged.

## Assumptions

- InputMethodKit provides the default click-outside commit only when the input
  controller recognizes `keyDown` alone.
- KnowType does not need `IMKMouseHandling` while it relies on that default.
- Installed cross-host acceptance remains a manual release gate because package
  tests cannot drive the macOS InputMethodKit host interaction.
