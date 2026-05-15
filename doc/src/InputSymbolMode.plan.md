# InputSymbolMode

`InputSymbolMode.swift` contains the local punctuation-mode layer for the input-method target.

- `InputSymbolMode` models current punctuation output as `chinese` or `english`.
- `InputSymbolTransformer` maps ASCII punctuation to Chinese punctuation in Chinese mode and preserves ASCII punctuation in English mode.
- `InputSymbolCommitPolicy` appends punctuation to the committed candidate text, or to raw input when no candidate commit is available.
- The IMK controller owns the current mode for the active controller session. `Option + .` toggles the mode; this can later be backed by settings persistence without changing key mapping or commit policy.
