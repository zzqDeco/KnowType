# CandidatePanelState

## Responsibility

`CandidatePanelState` tracks visible rows, selection, paging, and shortcut
mapping for the candidate panel.

## Boundaries

- It is UI state, not correction or provider logic.
- Candidate row construction stays in `CandidatePanelRenderer` and
  `InputCandidateListBuilder`.

## Behavior Notes

- Numeric shortcuts are page-local for visible rows.
- PageDown and PageUp preserve the selected row's visible offset on the target
  page and clamp on short final pages.
- Adaptive horizontal mode caps the effective visible row count separately from
  vertical-list mode.

## Tests

- `CandidatePanelStateTests`
- `CandidatePanelRendererTests`
- `InputKeyCommandMapperTests`
