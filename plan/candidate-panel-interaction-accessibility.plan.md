# Candidate Panel Interaction And Accessibility Hardening

Status: Active

## Summary

- Complete the interaction and accessibility slice of issue #184 after the
  candidate-anchor probe-budget fix.
- Prevent stale symbol commits, make VoiceOver candidate actions functional,
  and keep pointer-driven paging predictable across trackpads and mouse wheels.

## Scope

- Map Command/Control key-down events to an explicit host-shortcut intent.
- Cancel an active symbol-candidate session before passing a host shortcut back
  to the client; key-up and flags-changed behavior remains unchanged.
- Preserve each enabled accessibility row's `CandidatePanelSelection` and route
  its press action through the existing candidate commit handler.
- Accumulate trackpad deltas and emit at most one page action per gesture;
  discard momentum and throttle phase-less wheel paging for 120 ms.
- Keep the delivered `CandidateAnchorResolver` probe budgets and fallback order
  unchanged.

## Implementation

- `InputKeyCommandMapper` emits `.hostShortcut` only for Command/Control
  key-down.
- `InputControllerCoordinator` restores or hides the symbol overlay before
  returning `false` for `.hostShortcut`, allowing the host to handle the key.
- `CandidatePanelAccessibilityRow` retains its real optional selection. Only
  enabled rows with a selection implement a successful accessibility press.
- `CandidatePanelScrollPagingState` owns gesture accumulation, momentum
  rejection, direction mapping, and the traditional-wheel cooldown.

## Test Plan

- `swift test --filter InputKeyCommandMapperTests`
- `swift test --filter CandidatePanelAccessibilityTests`
- `swift test --filter CandidatePanelWindowControllerTests`
- `swift test --filter testHostShortcutCancelsIdleSymbolSessionBeforeFollowingSpace`
- `swift test --filter CandidateAnchor`
- `swift test`
- `git diff --check`

## Assumptions

- AppKit delivers synchronous accessibility press callbacks on the main thread.
- Momentum events never initiate a new candidate-page action.
- Manual TextEdit, Chrome/Electron, trackpad, mouse-wheel, and VoiceOver checks
  remain release acceptance work outside unit-test automation.
