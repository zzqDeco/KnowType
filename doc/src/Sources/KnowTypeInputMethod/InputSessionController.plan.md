# InputSessionController

`InputSessionController` owns the MVP input-method session state machine.

## State

- `mode`: explicit IME mode for `empty`, `composing`, `candidate`, `aiPending`, `polish`, and `ascii` sessions.
- `rawInput`: latest raw composing text from the input method host.
- `latestSuggestion`: latest `SuggestionResponse` from `SessionSuggestionPipeline`.
- `latestSuggestionRawInput`: raw input that produced `latestSuggestion`, used to reject stale candidate actions.
- `selectedPrefixIndex`: active correction candidate index, defaulting to `0` after each update.
- `selectedContinuationIndex`: active continuation candidate index, defaulting to `nil` after each update.
- `polishRequested`: whether the current session requested explicit polish.

## Behavior

- `update(rawInput:appBundleID:locale:)` builds an `InputContext`, moves non-protected composing text to `aiPending`, asks the pipeline for suggestions, stores the result, and resets selection state.
- Level 0 protected text uses a no-provider pipeline path so cloud providers are not called, then clears continuation candidates so protected input commits unchanged.
- `selectPrefix(index:)` and `selectContinuation(index:)` mutate selection only when the requested index exists.
- `reset()` clears the session back to `empty`.
- `handle(action:)` delegates commit assembly to `InputCompositionController` while applying session selection:
  - Space commits the selected prefix only.
  - Tab commits the selected prefix plus selected or first continuation.
  - Option-number commits the continuation mapped to that global shortcut; `Option+1` commits continuation index `0`, matching the first continuation also available through `Tab`, and continuation pages do not reset those shortcut mappings.
  - Option-R marks `polishRequested` and returns `.polishRequested(rawInput)`.
- `InputSessionCommitPolicy` is the shared action policy used by the IMK bridge for native candidate selections, stale-suggestion fallback, and numeric candidate shortcuts. Production callers can disable synchronous fallback while an async suggestion is pending so key handling does not run large-lexicon decoding on the main path.
- The IMK bridge handles visible numeric prefix shortcuts as page-local rows. `0` still commits raw input when current correction candidates exist, and unmatched digits append to the composing buffer rather than selecting hidden off-page candidates.
