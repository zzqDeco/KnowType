# InputSessionController

`InputSessionController` owns the MVP input-method session state machine.

## State

- `rawInput`: latest raw composing text from the input method host.
- `latestSuggestion`: latest `SuggestionResponse` from `InputMethodPipeline`.
- `selectedPrefixIndex`: active correction candidate index, defaulting to `0` after each update.
- `selectedContinuationIndex`: active continuation candidate index, defaulting to `nil` after each update.
- `polishRequested`: whether the current session requested explicit polish.

## Behavior

- `update(rawInput:appBundleID:locale:)` builds an `InputContext`, asks the pipeline for suggestions, stores the result, and resets selection state.
- Level 0 protected text uses a no-provider pipeline path so cloud providers are not called, then clears continuation candidates so protected input commits unchanged.
- `selectPrefix(index:)` and `selectContinuation(index:)` mutate selection only when the requested index exists.
- `handle(action:)` delegates commit assembly to `InputCompositionController` while applying session selection:
  - Space commits the selected prefix only.
  - Tab commits the selected prefix plus selected or first continuation.
  - Option-number commits the continuation shown with that shortcut; `Option+1` commits continuation index `0`, matching the first continuation also available through `Tab`.
  - Option-R marks `polishRequested` and returns `.polishRequested(rawInput)`.
