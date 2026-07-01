# CandidatePanelRowBuilder

## Responsibility

`CandidatePanelRowBuilder` is the single source of truth for candidate-panel row
ordering and row selection identity.

It converts a `CandidatePanelViewModel` into:

- fixed rows, currently commit-only preedit rows that do not consume paging slots
- pageable rows, including raw input, prefix candidates, AI rows, and legacy
  continuation rows

## Boundaries

- It does not draw UI, assign shortcut labels, or measure layout.
- It does not own correction, Rime, AI recommendation generation, or commit
  behavior.
- `CandidatePanelState` consumes its pageable row selections for keyboard
  navigation, paging, and number-shortcut eligibility.
- `CandidatePanelRenderer` consumes the same row items to build render rows and
  accessibility labels.

## Behavior Notes

- Preedit rows are fixed rows with no `CandidatePanelSelection`, no numeric
  shortcut eligibility, and no default selection.
- Raw input is a pageable row only when there are no visible suggestions or
  preedit rows.
- The AI row appears after the first prefix row when prefixes exist, or as the
  first pageable row when no prefix rows exist.
- Disabled AI status rows have no selection identity and are skipped by
  keyboard, mouse, and number-shortcut selection.
- Ready AI rows are selectable, but they are not default selections. Users must
  accept them through Tab, Option-number, click, hover, or another explicit
  selection action rather than ordinary Space accidentally committing an
  auto-selected AI row.
- Prefix rows are the only rows marked number-shortcut eligible.
- Full and segment candidate selection identity is derived from the candidate
  raw range in the builder so state and rendering cannot drift.

## Tests

- `CandidatePanelRowBuilderTests`
- `CandidatePanelStateTests`
- `CandidatePanelRendererTests`
