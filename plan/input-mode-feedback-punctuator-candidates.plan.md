# Input Mode Feedback Punctuator Candidates

## Summary

Add mature-IME punctuation behavior to KnowType's input hot path: mode changes
become visible, comma/period no longer disappear at native page boundaries, and
ambiguous Chinese punctuation opens symbol candidates instead of forcing a
single replacement.

This slice follows the Rime-style separation between text mode, punctuation
style, and symbol width. It does not change Rime schema data, AI requests,
candidate ordering, host compatibility policy, or install scripts.

## Scope

- Add `InputPunctuatorRuntime` for direct punctuation commits, symbol-candidate
  sessions, and pass-through decisions.
- Keep comma/period paging behavior Rime-compatible while falling back to
  `，`/`。` when native paging does not change the snapshot.
- Add panel-backed symbol candidates for ambiguous punctuation keys in Chinese
  punctuation mode.
- Add transient mode-status feedback for `Option + .` and `Option + /`, plus a
  read-only mode-status item in the input-method menu.
- Update Settings, README, interface docs, and source notes for the new
  punctuation model.

## Implementation

- `InputPunctuatorRuntime` returns `.commit`, `.showCandidates`, or
  `.passThrough` while preserving the existing `InputModeState` fields:
  `textMode`, `punctuationMode`, and `symbolWidth`.
- Chinese punctuation half-width mode directly commits common sentence
  punctuation, paired Chinese quotes, ellipsis, em dash, and bracket pairs.
  Code/path/operator symbols stay ASCII unless full-width mode is explicitly
  enabled.
- Symbol-candidate sessions reuse the existing candidate panel frame channel.
  `Space` or `1` commits the first visible symbol, number keys commit their
  visible symbol, arrows move selection, `Escape` cancels, and other printable
  input cancels before normal handling.
- Symbol candidates do not trigger AI requests, Rime buffer mutation, prefix
  selection learning, or provider context changes.
- Mode-status rows are disabled, transient panel rows with privacy-safe text
  such as `中 · 中文标点 · 半角`; the next real input key clears the status row
  before publishing composition or symbol candidates, and no user input text or
  candidate text is logged.

## Test Plan

- `swift test --quiet --filter InputPunctuatorRuntimeTests`
- `swift test --quiet --filter InputSymbolModeTests`
- `swift test --quiet --filter InputKeyCommandMapperTests`
- `swift test --quiet --filter CandidatePanelRowBuilderTests`
- `swift test --quiet --filter CandidatePanelRendererTests`
- `swift test --quiet --filter CandidatePanelWindowControllerTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test`
- `git diff --check`

Manual acceptance:

- TextEdit/Chrome: `nihao,` and `nihao.` commit the Chinese candidate plus
  `，`/`。`.
- TextEdit/Chrome: paired `"` / `'`, `^ -> ……`, `_ -> ——`, and `-` remains
  ASCII.
- `/` opens symbol candidates; `Space` commits `、`, `2` commits `/`, and
  `Escape` cancels.
- Switching among Codex, VS Code, Xcode, Terminal, and ordinary text apps keeps
  the same process-global text, punctuation, and width state.
- `Option + .` and `Option + /` show the transient mode-status row and the input
  menu reports the current mode.

## Assumptions

- The first symbol-candidate slice uses a fixed built-in candidate table rather
  than reading Rime punctuator YAML.
- Shift/CapsLock text-mode switching and selected-text reconversion remain
  follow-up work.
- English punctuation mode stays direct ASCII for ambiguous symbols so code
  typing is not interrupted by a candidate panel.
