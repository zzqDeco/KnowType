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

## Tests

- `CandidatePanelLayoutEngineTests`
- `CandidatePanelWindowControllerTests`
