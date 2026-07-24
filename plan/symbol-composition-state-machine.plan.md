# Symbol Composition State Machine

## Summary

- Unify punctuation production into direct output and ambiguous-symbol
  candidates.
- Make one active-session runtime own mutually exclusive text and symbol
  composition state so the candidate panel is a projection rather than a
  second source of truth.

## Scope

- Add the internal `InputSymbolRule.direct` and `.candidates` production
  contract while retaining deprecated public punctuator adapters.
- Add `ActiveInputSession`, `TextComposition`, `SymbolComposition`, and
  value-only symbol transition plans.
- Move symbol selection, paging, repeated-trigger, commit, cancel, focus,
  shortcut, and printable replay decisions into the active-session runtime.
- Keep Rime calls, host writes, AI cancellation, panel publication, and replay
  execution in `InputControllerCoordinator`.
- Do not add symbol marked-text preview, persistence, settings, search, or new
  symbol catalogs. Marked-text lifecycle work remains in Issue #208.

## Implementation

- Direct punctuation resolves its final Chinese, ASCII, full-width, decimal, or
  contextual-quote text before returning from the punctuator.
- Text and symbol sessions use one monotonically increasing composition id
  domain. A symbol session captures immutable candidates, its trigger, host
  identity and cursor ranges, plus explicit lifecycle policies.
- Text-to-symbol transitions commit the text session first and create the
  symbol session only after text state reaches idle with a usable client.
- Navigation and paging update symbol selection and revision with clamped
  boundaries. Repeating the trigger advances selection.
- Space, Return, visible numbers, mouse selection, explicit commit, valid focus
  loss, and click-outside commit the selected symbol. Escape, Backspace, reset,
  controller close, missing-client lifecycle events, host shortcuts, and input
  mode generation changes cancel it.
- Other printable input produces one commit-and-replay plan. The coordinator
  commits the symbol, clears the panel, then handles the original intent once
  from idle without recursion.
- Symbol sessions do not mutate Rime, schedule AI, record prefix selection, or
  expose symbol text in diagnostics.

## Test Plan

- Cover direct/candidate rules, contextual punctuation, candidate ordering, and
  deprecated-adapter compatibility.
- Cover active-session exclusivity, ids, revisions, clamped navigation,
  paging, repeated triggers, lifecycle policies, cancellation, and one-shot
  replay.
- Cover coordinator text-to-symbol ordering, missing-client failure, panel
  projection, numeric and printable replay, host shortcuts, focus behavior, and
  absence of Rime/AI/prefix-learning side effects.
- Run focused punctuator, active-session, coordinator, and candidate-panel
  tests, then `swift test`, `./scripts/perf-input-hotpath.sh`, and
  `git diff --check`.
- Build an installable version for user-run TextEdit, browser/Electron, and
  Terminal acceptance.

## Assumptions

- Candidate mappings, order, page size, width rules, and quote behavior remain
  unchanged.
- Host-level ASCII passthrough remains a writer compatibility decision, not a
  symbol rule.
- Issue #208 will add symbol marked-text preview and the remaining full IMK
  lifecycle without changing this session ownership model.

