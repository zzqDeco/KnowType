# KnowType Space / Digit Direct Passthrough

## Summary

- Status: Active.
- Branch: `fix/direct-space-digit-passthrough`.
- Goal: make idle Space and digit keys behave like ordinary text input, while keeping Rime composition Space and numeric candidate selection unchanged.

## Scope

- Fix idle key handling in the IMK coordinator only.
- Preserve Rime candidate selection for active composition, including hidden-panel number selection.
- Do not change input-source registration, settings UI, Rime schemas, AI provider behavior, or release flow.

## Implementation

- Treat active text composition as `rawBuffer` non-empty, resolved `CompositionBuffer` segments, or any native Rime snapshot with active composition, including candidate-only snapshots.
- When no active text composition exists, Space and `0...9` use explicit `insertText` passthrough with the current marked replacement range when one lingers, otherwise `NSNotFound`, and clear stale panel/suggestion/native snapshot state.
- When Rime composition is active, `1...9` continue to select current-page candidates. Out-of-range numbers are consumed by the active composition and do not append literal digits or commit AI.
- Keep `0` raw-composition shortcut behavior for visible correction candidates; idle `0` passes through as a normal digit.

## Test Plan

- Unit tests cover idle Space passthrough, text-only and key-code digit passthrough, stale marked-range replacement, fast `Space` then `Space`, active Rime number selection, hidden-panel and candidate-only number selection, out-of-range active digits, and AI-ready ordinary digit behavior.
- Required validation: `swift test --quiet`, `./scripts/smoke-inputmethod-install.sh`, `./scripts/perf-input-hotpath.sh`, and `git diff --check`.

## Assumptions

- Direct digit passthrough applies only when no text composition is active.
- Direct passthrough is not recorded as AI context or lexical-selection history.
- Explicit insertion is preferred over returning `false` because IMK fallback behavior differs by host app.
