# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- candidate panel view model
- shortcut-to-commit behavior
- async suggestion pipeline wiring
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`

The full macOS app bundle and IMK controller target should be added after the core package is stable.
