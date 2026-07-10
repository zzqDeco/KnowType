# InputSymbolMode

## Responsibility

`InputSymbolMode.swift` owns local punctuator decisions and full-width symbol
conversion for one key event.

## Boundaries

- Process-wide mode transitions belong to `InputModeStateMachine` and
  `ProcessInputModeStateRuntime`.
- Rime candidate paging and schema handling run before this fallback layer.
- Document context acquisition belongs to `InputPunctuationContextResolver` and
  the IMK client seam; this file receives only classified context.

## Behavior Notes

- `InputPunctuatorRuntime` returns direct commit, symbol candidates, or
  pass-through without changing global mode state.
- Chinese punctuation supports sentence punctuation, paired Chinese quotes,
  ellipsis, em dash, bracket pairs, and panel-backed ambiguous symbols.
- ASCII mode uses English punctuation. Chinese mode may temporarily use English
  punctuation after a manual override.
- Symbol width remains independent and full-width mapping is applied only when
  explicitly enabled.
- An idle period with `previousCharacterKind == asciiDigit` commits `.` before
  punctuation and width mapping. This exception does not apply to active Rime
  composition or comma.
- Quote pairing state is coordinator-local and resets whenever a newer global
  mode generation is observed.

## Tests

- `InputPunctuatorRuntimeTests`
- `InputSymbolModeTests`
- `InputControllerCoordinatorTests`
