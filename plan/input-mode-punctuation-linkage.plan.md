# Input Mode Punctuation Linkage

Status: Active

## Summary

Replace app-specific input-mode defaults with one process-wide state machine.
Chinese input links to Chinese punctuation, ASCII input links to English
punctuation, a Chinese-mode manual punctuation override lasts until the next
text-mode switch, and symbol width remains independent. Add a narrow ASCII
period exception immediately after a digit.

This follows the mode ownership used by mature IMEs while avoiding the former
surprise where changing apps silently changed punctuation.

## Scope

- Add pure `InputModeStateMachine` state and a thread-safe runtime shared by all
  production IMK coordinators.
- Stop applying bundle-specific text, punctuation, or width defaults.
- Keep only one persisted global default width and retain old preference shapes
  and keys as read-only compatibility data.
- Classify the character before the caret only for an idle period and apply the
  numeric-period exception without logging document text.
- Simplify Settings and update mode, punctuator, coordinator, host-seam, and
  interface documentation.

Non-goals: no Rime schema, candidate ranking, AI/provider, host-write contract,
installation, or registration changes.

## Implementation

- State contains `textMode`, `punctuationMode`, `symbolWidth`,
  `punctuationSource`, and a monotonic generation.
- `Option + /` changes text mode, links punctuation to the destination, and
  clears manual punctuation source. `Option + .` changes punctuation only in
  Chinese mode. `Shift + Space` changes width only.
- `KnowTypeInputController` injects one process runtime. Coordinators compare
  generation each turn and reset quote pairing and symbol-candidate overlays
  after external transitions.
- `InputControllerClient.characterBeforeCaret()` defaults to unavailable. The
  IMK adapter requests one preceding UTF-16 unit only for a collapsed caret.
- `InputPunctuationContextResolver` prefers client context and otherwise uses a
  client- and expected-caret-bound insertion fallback.
- An idle `.` after ASCII `0...9` commits `.` before punctuation or full-width
  mapping. Composition, selection, unknown context, and comma use the normal
  punctuator path.
- Save `input.global.symbolWidth`; migrate from legacy default width when the
  new key is absent. The process runtime tracks the observed configured width
  separately so a new coordinator cannot overwrite a temporary Shift+Space
  choice. Do not delete or rewrite old mode keys.

## Test Plan

- `swift test --quiet --filter InputModeStateMachineTests`
- `swift test --quiet --filter InputPunctuatorRuntimeTests`
- `swift test --quiet --filter InputSymbolModeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter InputModePreferencesViewModelTests`
- `swift test --quiet --filter InputMethodMenuBuilderTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

Manual acceptance covers TextEdit, Chrome, Codex, VS Code, and Terminal: app
switches preserve mode; Chinese/ASCII switches relink punctuation; Chinese
manual punctuation expires on the next text switch; decimal and numbered-list
periods stay ASCII; full-width remains independent; candidate overlays do not
drift or retain stale symbol sessions.

## Assumptions

- Global means one input-method host process, not persistence across process or
  system restart.
- ASCII mode cannot enable Chinese punctuation.
- Numeric context covers only an immediately preceding ASCII digit plus period.
- A client document read is best-effort; unknown context safely falls back to
  ordinary punctuation.
