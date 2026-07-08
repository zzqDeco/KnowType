# InputSymbolMode

`InputSymbolMode.swift` contains the local punctuation conversion layer for the input-method target. Pure input-mode state is shared through `KnowTypeCore` so the settings app and IMK runtime read the same preference model.

- `InputTextMode` models Chinese vs ASCII input intent so later controller state can align with mature IME session options.
- `InputSymbolMode` models current punctuation output as `chinese` or `english`.
- `InputSymbolWidth` models half-width vs full-width symbol output independently from punctuation language.
- `InputModeState` groups text mode, punctuation mode, and symbol width as input attributes.
- `InputModePreferences` stores normal-app and code-app default states.
- `InputModePreferenceRuntime` owns the active controller state, reloads defaults when saved preferences or app context change, and preserves session-local toggles when saved preferences are unchanged.
- `InputModeAppPolicy` applies those preferences; code and terminal contexts use the separate code-app preference path. The built-in code-app default keeps symbols half-width and punctuation English unless the user changes the code-app preference; non-terminal code apps still inherit the normal Chinese text-mode default so composition can start immediately.
- `InputSymbolTransformer` maps ASCII punctuation through `InputModeState`, using Chinese sentence punctuation, brackets, and book-title marks in Chinese punctuation mode, preserving code/path/operator symbols as ASCII in half-width mode, and supporting full-width symbol output only when `InputSymbolWidth.fullWidth` is active.
- `InputSymbolCommitPolicy` appends punctuation to the committed candidate text, or to raw input when no candidate commit is available.
- The IMK controller loads persisted preferences at startup and refreshes them at the next composition or direct symbol input. `Option + .` toggles the session state without rewriting saved preferences.
