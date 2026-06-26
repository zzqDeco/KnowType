# Input Client Placeholder Composition

## Summary

- Status: Delivered.
- Branch: `fix/input-client-placeholder-composition`.
- Goal: align commit-only host composition with mature IMK behavior so
  compatibility hosts do not swallow Chinese input when inline preedit is unsafe.

## Implementation

- `commitOnlyComposition` keeps its public raw value, but now writes a
  full-width-space marked-text placeholder during active composition instead of
  skipping `setMarkedText`.
- KnowType tracks the client that owns its marked text and clears only that
  owned mark before `insertText` commits or composition teardown.
- Commit-only placeholder writes schedule the same delayed candidate re-anchor
  as inline composition, so Codex, Electron, editor, and terminal hosts are not
  dependent on the first stale caret rectangle.
- Coordinator-level client fallback is limited to active composition and
  lifecycle teardown; idle printable input with a missing client passes through
  instead of using a possibly stale host client.

## Test Plan

- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputClientCompatibilityPolicyTests`
- `swift test --quiet --filter InputSymbolModeTests`
- `swift test`
- `git diff --check`

## Assumptions

- Placeholder text is U+3000 full-width space, matching the compatibility pattern
  used by mature macOS IMEs for non-inline preedit.
- This change does not add settings UI and does not change Rime schemas, AI
  provider behavior, input-source registration, or install scripts.
