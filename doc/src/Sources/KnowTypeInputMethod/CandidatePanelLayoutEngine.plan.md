# CandidatePanelLayoutEngine

## Responsibility

`CandidatePanelLayoutEngine` measures candidate rows and returns the layout plan
used by the AppKit panel.

## Boundaries

- It owns panel size, orientation, row frames, text limits, and screen-edge
  avoidance.
- Row semantics stay in `CandidatePanelRenderer`.
- Window lifecycle stays in `CandidatePanelWindowController`.

## Behavior Notes

- Adaptive layout prefers horizontal pages for compact candidates and switches
  to vertical rows for long phrases.
- Constrained vertical layouts compress row height and spacing before hiding the
  panel.
- Layout must never drop selectable rows after shortcut labels are assigned.
- Shortcut labels are measured by the layout engine. Horizontal rows use each
  row's own shortcut width. Vertical rows align only rows that have shortcuts to
  the current page's widest shortcut label. Rows without shortcuts reserve no
  shortcut slot or shortcut-text spacing.
- `CandidatePanelLayoutItem.shortcutLabelWidth` is the only shortcut width the
  AppKit content view should constrain to; rendering code must not reintroduce a
  fixed reserved shortcut width.

## Tests

- `CandidatePanelLayoutEngineTests`
- `CandidatePanelWindowControllerTests`
