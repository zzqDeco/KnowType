# InputSymbolMode

## Responsibility

`InputSymbolMode.swift` owns local symbol rules and full-width character
conversion for one key event.

## Boundaries

- Process-wide mode transitions belong to `InputModeStateMachine` and
  `ProcessInputModeStateRuntime`.
- Rime candidate paging and schema handling run before this fallback layer.
- Document context acquisition belongs to `InputPunctuationContextResolver` and
  the IMK client seam; this file receives only classified context.

## Behavior Notes

- The production contract is only `InputSymbolRule.direct` or
  `InputSymbolRule.candidates`. It computes final output before returning and
  never represents host passthrough as a symbol product mode.
- Deprecated public `InputPunctuatorDecision` and
  `InputSymbolCandidateSession` adapters remain for SwiftPM source
  compatibility; the coordinator does not use them.
- Chinese punctuation supports sentence punctuation, paired Chinese quotes,
  ellipsis, em dash, bracket pairs, and panel-backed ambiguous symbols.
- ASCII mode uses English punctuation. Chinese mode may temporarily use English
  punctuation after a manual override.
- Character width remains independent. Full width maps U+0021 through U+007E
  with the Unicode full-width offset and maps U+0020 to U+3000; controls, Tab,
  newline, and non-ASCII text are unchanged.
- An idle period with `previousCharacterKind == asciiDigit` commits `.` before
  punctuation and width mapping. This exception does not apply to active Rime
  composition or comma.
- Chinese half-width quote decisions prefer opening/closing caret context and
  use coordinator-local alternation only when context is unknown. Fallback
  state resets after external delete, focus/selection changes, and newer global
  mode generations.
- Candidate mappings and ordering are stable; session ownership and selection
  belong to `InputActiveSessionRuntime`.

## Tests

- `InputPunctuatorRuntimeTests`
- `InputSymbolModeTests`
- `InputControllerCoordinatorTests`
