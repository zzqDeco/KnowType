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
- Commit-only preedit is stored in the view model and can make the panel
  visible, but it has no `CandidatePanelSelection`, no numeric shortcut, and no
  raw-input fallback selection.
- Disabled AI status rows are visible rows but have no selection identity, no
  numeric shortcut, and are skipped by keyboard and mouse selection.
- `selectVisibleRow` is the shared path for hover/click selection and only
  accepts enabled rows on the current page.
- PageDown and PageUp preserve the selected row's visible offset on the target
  page and clamp on short final pages.
- Adaptive horizontal mode caps the effective visible row count separately from
  vertical-list mode.

## Tests

- `CandidatePanelStateTests`
- `CandidatePanelRendererTests`
- `InputKeyCommandMapperTests`
