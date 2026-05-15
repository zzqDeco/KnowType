# Symbol Mode And Input Behavior

## Summary

This branch adds MVP Chinese/English punctuation behavior on top of the mature input foundation.

- Default punctuation mode is Chinese.
- `Option + .` toggles punctuation mode between Chinese and English for the current input controller session.
- Plain ASCII punctuation is treated as symbol input instead of entering the pinyin buffer.
- With an active composition, punctuation commits the current Space-equivalent prefix/candidate plus the mapped punctuation.
- With no active composition, punctuation is inserted directly.
- Existing numeric behavior remains: `0` commits raw composition, visible numbers select visible prefix rows, and unmatched digits continue composing.

## Test Plan

- `swift test --filter InputKeyCommandMapperTests`
- `swift test --filter InputSymbolModeTests`
- `swift test --filter InputCompositionControllerTests`
- `swift test`
