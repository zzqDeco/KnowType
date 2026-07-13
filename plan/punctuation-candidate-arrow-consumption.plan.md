# Punctuation Candidate Arrow Consumption

## Summary

- Consume responder-chain arrow and paging commands while a punctuation or
  symbol candidate session is active.
- Cover the InputMethodKit keybinding callback path in addition to the existing
  raw key-event path so navigation cannot also move the host caret or selection.

## Scope

- Normalize standard AppKit responder navigation selector names into existing
  candidate-navigation intents.
- Route `IMKInputController.didCommand(by:client:)` through the coordinator's
  existing intent handler and return its handled result unchanged.
- Preserve candidate ordering, clamped boundary navigation, Rime behavior,
  punctuation mapping, AI behavior, mouse commit, and host write policy.
- Keep `recognizedEvents(_:)` restricted to `keyDown` so InputMethodKit retains
  default click-outside composition commit behavior.

## Implementation

- `InputKeyCommandMapper` recognizes the four directional selectors,
  `pageUp:`/`pageDown:`, and their `AndModifySelection:` variants. Unknown
  selectors remain pass-through.
- `InputControllerCoordinator` maps command-selector names through the same
  latency trace and `handle(intent:client:)` path used by raw key events.
- Active symbol-candidate navigation always returns handled, including at
  clamped list boundaries, without writing marked or inserted host text.
- `KnowTypeInputController` adapts the callback client, converts the selector
  with `NSStringFromSelector`, and logs only selector name and handled state.

## Test Plan

- Cover all supported and unsupported selector-name mappings.
- Verify active symbol candidates consume navigation, clamp at both boundaries,
  preserve host selection, and perform no host text writes.
- Verify raw keyCode and command-selector entry points produce the same
  selection and handled result, then pass through after commit or cancellation.
- Run focused mapper, coordinator, candidate-state, and recognized-event tests,
  followed by `swift test` and `git diff --check`.
- Run install smoke, release installation, strict diagnostics, and manual host
  acceptance in TextEdit plus a browser or Electron host.

## Assumptions

- Candidate boundaries remain clamped rather than wrapping.
- The change adds no public API, persistence format, configuration, diagnostic
  switch, or user-data migration.
- Unknown responder commands must remain available to the focused host.
