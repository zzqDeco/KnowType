# CandidatePanelAppearance

## Responsibility

- Centralizes the AppKit candidate panel's visual metrics and semantic colors.
- Defines native row heights, insets, spacing, corner radii, border width,
  material choice, candidate fonts, shortcut fonts, and snapshot color variants.
- Produces the `CandidatePanelLayoutConfiguration` used by
  `CandidatePanelLayoutEngine` so measured layout and rendered AppKit rows share
  the same sizing rules.

## Boundaries

- It is an input-method UI style object only.
- It must not decide candidate ordering, AI eligibility, provider behavior,
  prefix-lock rules, or commit policy.
- Row semantics stay in `CandidatePanelRenderer`; selection and paging stay in
  `CandidatePanelState`; AppKit view construction stays in
  `CandidatePanelWindowController`.

## Behavior Notes

- Native rendering uses dynamic system colors and AppKit popover material.
- Snapshot rendering uses fixed light/dark colors so PNG regression tests do not
  depend on the current system accent or appearance.
- Disabled AI status rows use weaker text colors but keep the same measured
  layout path as enabled rows.

## Tests

- `CandidatePanelLayoutEngineTests`
- `CandidatePanelWindowControllerTests`
- `CandidatePanelSnapshotTests`
