# Input Mode Preferences

Status: Absorbed by
[input-mode-punctuation-linkage.plan.md](input-mode-punctuation-linkage.plan.md).

## Goal

Persist the one restart-level input preference that remains product state: the
global character width.

## Behavior

- `UserDefaultsInputModePreferenceStore` stores `input.global.symbolWidth` in the
  shared `com.knowtype.preferences` defaults domain.
- The input-method host starts in linked Chinese text/Chinese punctuation and
  the saved global width. App and window changes do not reload mode.
- `Option + /`, `Option + .`, and `Shift + Space` mutate the process runtime for
  the host lifetime; only width is persisted for the next host process.
- Legacy default/code-app fields remain readable migration data but do not
  influence runtime mode or acceptance.

## Verification

```bash
swift test --filter InputModePreferencesTests
swift test --filter InputModePreferencesViewModelTests
swift test --filter InputSymbolModeTests
swift test
git diff --check
```
