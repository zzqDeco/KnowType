# Candidate Page Navigation

Goal: make candidate paging behave more like a mature list navigation model while preserving the compact 9-row candidate window.

## Scope

- Keep arrow navigation moving one selectable row at a time.
- Keep visible numeric shortcuts page-local.
- Change PageDown/PageUp to preserve the selected row's visible offset on the target page instead of always jumping to the first row.
- Clamp the preserved offset on short final pages.

## Validation

- Unit tests cover PageDown/PageUp offset preservation, short-page clamping, page-boundary arrow movement, and numeric shortcut selection on the visible page.
