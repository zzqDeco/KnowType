# Input Mode And Punctuation State

Status: Absorbed by
[input-mode-punctuation-linkage.plan.md](input-mode-punctuation-linkage.plan.md)
and [rime-mode-option-sync.plan.md](rime-mode-option-sync.plan.md).

## Summary

This branch upgrades the PR #26 punctuation slice into an explicit input-mode state layer.

The implementation follows the engineering direction from the reference IMEs:

- Squirrel keeps ascii/full-shape/punctuation behavior as session options rather than UI formatting.
- McBopomofo and vChewing route punctuation through deterministic local state before candidate/provider work.
- Toyimk and macOS IMKit samples keep the IMK controller as a thin event bridge.

KnowType now models:

- `InputTextMode`: Chinese vs ASCII intent.
- `InputSymbolMode`: Chinese vs English punctuation.
- `InputSymbolWidth`: half-width vs full-width symbols.
- `InputModeState`: the active session-local input attributes.
- `ProcessInputModeStateRuntime`: one host-lifetime state shared across apps.

## Scope

- Keep `KnowTypeInputController` as the IMK bridge and move mode decisions into typed policy objects.
- Preserve PR #26 behavior: plain punctuation commits composition plus punctuation, and `Option + .` toggles punctuation mode.
- Add full-width symbol mapping as a typed state capability; the current runtime shortcut is `Shift + Space`.
- Keep host compatibility separate from mode state. App or window changes do not
  reload text, punctuation, or width defaults.

## Non-Goals

- Persistent settings storage.
- Candidate-window status badges.
- Symbol table candidate UI.
- A full immutable IME FSM migration.

Those remain separate follow-up branches so this PR stays reviewable.

## Test Plan

- `swift test --filter InputSymbolModeTests`
- `swift test --filter InputKeyCommandMapperTests`
- `swift test`
