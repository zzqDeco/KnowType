# InputSymbolMode

`InputSymbolMode.swift` contains the local punctuation conversion layer for the input-method target. Pure input-mode state is shared through `KnowTypeCore` so the settings app and IMK runtime read the same preference model.

- `InputTextMode` models Chinese vs ASCII input intent so later controller state can align with mature IME session options.
- `InputSymbolMode` models current punctuation output as `chinese` or `english`.
- `InputSymbolWidth` models half-width vs full-width symbol output independently from punctuation language.
- `InputModeState` groups text mode, punctuation mode, and symbol width as input attributes.
- `InputModePreferences` stores normal-app and code-app default states.
- `InputModeAppPolicy` applies those preferences; code and terminal contexts default to English half-width punctuation unless the user changes the code-app preference.
- `InputSymbolTransformer` maps ASCII punctuation through `InputModeState`, using Chinese punctuation in Chinese mode, preserving ASCII in English half-width mode, and supporting full-width symbol output.
- `InputSymbolCommitPolicy` appends punctuation to the committed candidate text, or to raw input when no candidate commit is available.
- The IMK controller loads persisted preferences at startup and owns the current mode for the active controller session. `Option + .` toggles the session state without rewriting saved preferences.
