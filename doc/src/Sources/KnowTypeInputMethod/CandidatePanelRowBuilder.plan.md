# CandidatePanelRowBuilder

## Responsibility

`CandidatePanelRowBuilder` is the single source of truth for candidate-panel row
ordering and row selection identity.

It converts a `CandidatePanelViewModel` into:

- fixed rows, including transient mode-status rows and commit-only preedit rows
  that do not consume paging slots
- pageable rows, including symbol candidates, raw input, prefix candidates, AI
  rows, and legacy continuation rows

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
- Mode-status rows are fixed disabled rows with no numeric shortcut and a
  privacy-safe accessibility label.
- Symbol-candidate sessions temporarily replace ordinary pageable rows with
  selectable symbol rows. They are number-shortcut eligible and commit through
  `CandidatePanelSelection.symbolCandidate`.
- Raw input is a pageable row only when there are no visible suggestions or
  preedit rows.
- The AI row appears after the first prefix row when prefixes exist, or as the
  first pageable row when no prefix rows exist.
- Disabled AI status rows have no selection identity and are skipped by
  keyboard, mouse, and number-shortcut selection.
- Pending AI status rows are spinner-only visually: the row keeps empty visible
  text, a fixed spinner accessory, and an explicit `AI 状态，AI 推荐中`
  accessibility label.
- Ready AI rows are selectable, but they are not default selections. Users must
  accept them through Tab, Option-number, click, hover, or another explicit
  selection action rather than ordinary Space accidentally committing an
  auto-selected AI row.
- Prefix rows and symbol-candidate rows are number-shortcut eligible.
- Full and segment candidate selection identity is derived from the candidate
  raw range in the builder so state and rendering cannot drift.

## Tests

- `CandidatePanelRowBuilderTests`
- `CandidatePanelStateTests`
- `CandidatePanelRendererTests`
