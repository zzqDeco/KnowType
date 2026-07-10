# InputKeyCommandMapper

## Responsibility

`InputKeyCommandMapper` translates key events and modifiers into typed input
actions.

## Boundaries

- It maps keys; it does not decide provider eligibility, candidate ranking, or
  marked-text writes.
- AppKit/IMK event access should remain isolated from core session logic.

## Behavior Notes

- `Option + .` toggles process-wide punctuation language while text mode is Chinese.
- `Option + /` toggles process-wide Chinese/ASCII text mode.
- `Shift + Space` toggles process-wide half-width/full-width characters.
- `Option + number` maps to continuation shortcuts.
- `Option + R` is the explicit polish path.
- Plain punctuation remains a symbol intent; the coordinator decides whether a composing native Rime session should consume `-`/`=`, `,`/`.` as page shortcuts before punctuation commit fallback.
- Unmatched digits can continue composing as literal digits when they are not
  visible shortcuts.

## Tests

- `InputKeyCommandMapperTests`
- `InputSymbolModeTests`
- `MVPAcceptanceTests`
