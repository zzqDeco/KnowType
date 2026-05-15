# Input Mode Preferences

## Goal

Persist KnowType punctuation preferences so Chinese punctuation, English punctuation, and full-width symbol behavior are no longer only session-local controller state.

## Behavior

- Pure input-mode models live in `KnowTypeCore`:
  - `InputTextMode`
  - `InputSymbolMode`
  - `InputSymbolWidth`
  - `InputModeState`
  - `InputModePreferences`
  - `InputModePreferenceRuntime`
  - `InputModeAppPolicy`
- `UserDefaultsInputModePreferenceStore` stores punctuation preferences in the shared `com.knowtype.preferences` defaults domain.
- The input-method controller reads preferences at controller startup and refreshes them when a new composition or direct symbol input begins:
  - normal apps use `defaultState`
  - code/terminal-style apps use `codeAppState`
- The SwiftUI Input settings tab can edit:
  - default punctuation language
  - default symbol width
  - code-app punctuation language
  - code-app symbol width
- `Option + .` remains a session-local toggle for the active controller session and is not written back to saved preferences.

## Verification

```bash
swift test --filter InputModePreferencesTests
swift test --filter InputModePreferencesViewModelTests
swift test --filter InputSymbolModeTests
swift test
git diff --check
```
