# CandidatePanelState

## Responsibility

`CandidatePanelState` tracks selection, paging, and shortcut state for the
candidate panel.

## Boundaries

- It is UI state, not correction or provider logic.
- Candidate row ordering and selection identity come from
  `CandidatePanelRowBuilder`.
- Rendering, labels, layout, and AppKit drawing stay outside this type.

## Behavior Notes

- Numeric shortcuts are page-local for visible rows.
- Page-local numeric shortcut eligibility is derived from the shared row model,
  not reimplemented in state.
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
- `CandidatePanelRowBuilderTests`
- `CandidatePanelRendererTests`
- `InputKeyCommandMapperTests`
