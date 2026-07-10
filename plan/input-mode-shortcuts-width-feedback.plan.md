# KnowType Input Mode Shortcuts Width Feedback

Status: Absorbed by
[input-mode-punctuation-linkage.plan.md](input-mode-punctuation-linkage.plan.md)
and [rime-mode-option-sync.plan.md](rime-mode-option-sync.plan.md).

## Summary

Add the missing runtime shortcut for the third input-mode dimension:
half-width/full-width characters. KnowType keeps text mode, punctuation language,
and character width independent, but each dimension now has an explicit shortcut
and the transient mode-status row shows the full current state.

## Key Changes

- `Option + /` toggles Chinese/ASCII text mode only.
- `Option + .` toggles Chinese/English punctuation only.
- `Shift + Space` toggles half-width/full-width characters only.
- Every mode toggle resets punctuator pairing state and publishes the existing
  transient mode-status row, for example `中 · 中文标点 · 全角`; the row clears
  when the next real input key starts composition, symbol candidates, commit, or
  passthrough.
- Plain `Space` remains candidate commit, U+0020, or U+3000 according to active
  composition and width; Command/Control modified Space stays unhandled so
  system shortcuts are not consumed.

## Test Plan

- `swift test --quiet --filter InputKeyCommandMapperTests`
- `swift test --quiet --filter InputSymbolModeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputMethodMenuBuilderTests`
- `swift test`
- `git diff --check`

## Assumptions

- `Shift + Space` is the default full-width/half-width runtime shortcut because
  it matches common mature Chinese IME behavior.
- All apps share the host-lifetime process mode. Host carrier compatibility does
  not select different text, punctuation, or width defaults.
