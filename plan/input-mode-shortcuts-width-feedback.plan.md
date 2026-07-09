# KnowType Input Mode Shortcuts Width Feedback

Status: Active

## Summary

Add the missing runtime shortcut for the third input-mode dimension:
half-width/full-width symbols. KnowType keeps text mode, punctuation language,
and symbol width independent, but each dimension now has an explicit shortcut
and the transient mode-status row shows the full current state.

## Key Changes

- `Option + /` toggles Chinese/ASCII text mode only.
- `Option + .` toggles Chinese/English punctuation only.
- `Shift + Space` toggles half-width/full-width symbols only.
- Every mode toggle resets punctuator pairing state and publishes the existing
  mode-status row, for example `中 · 中文标点 · 全角`.
- Plain `Space` remains candidate commit or normal space; Command/Control
  modified Space stays unhandled so system shortcuts are not consumed.

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
- Code-style apps keep their default Chinese composition + English punctuation
  + half-width symbols policy; users can still switch the active session or
  change saved settings.
