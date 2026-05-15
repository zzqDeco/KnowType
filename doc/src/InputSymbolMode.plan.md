# InputSymbolMode

`InputSymbolMode.swift` contains the local punctuation-mode layer for the input-method target.

- `InputTextMode` models Chinese vs ASCII input intent so later controller state can align with mature IME session options.
- `InputSymbolMode` models current punctuation output as `chinese` or `english`.
- `InputSymbolWidth` models half-width vs full-width symbol output independently from punctuation language.
- `InputModeState` groups text mode, punctuation mode, and symbol width as session-local input attributes.
- `InputModeAppPolicy` provides app defaults; code and terminal contexts start with English half-width punctuation while keeping the Chinese text pipeline available.
- `InputSymbolTransformer` maps ASCII punctuation through `InputModeState`, using Chinese punctuation in Chinese mode, preserving ASCII in English half-width mode, and supporting full-width symbol output.
- `InputSymbolCommitPolicy` appends punctuation to the committed candidate text, or to raw input when no candidate commit is available.
- The IMK controller owns the current mode for the active controller session. `Option + .` toggles the mode; this can later be backed by settings persistence without changing key mapping or commit policy.
