# KnowType Spotlight Candidate Panel Placement Plan

Status: Active

## Summary

Fix Spotlight/search overlay candidate panel occlusion by adding an explicit
candidate panel placement policy. The default text-input behavior continues to
prefer placing the panel below the caret, while Spotlight prefers placing the
panel above the caret so the search results area does not cover candidates.

## Implementation

- Add `CandidatePanelPlacementPreference` with `automatic`, `preferVisualBelow`,
  and `preferVisualAbove`.
- Add `CandidatePanelVerticalPlacement` to layout plans so diagnostics and tests
  can distinguish the actual side chosen.
- Thread placement preference from the input coordinator into
  `CandidatePanelWindowState` and `CandidatePanelLayoutEngine`.
- Treat `com.apple.Spotlight` as `preferVisualAbove`; all other apps keep
  `automatic`.
- Keep the existing `.popUpMenu` non-activating panel level and visible-frame
  clamping; this is a geometry fix, not a window-level escalation.

## Tests

- Layout defaults to visual-below placement when it fits.
- `preferVisualAbove` uses visual-above placement when it fits.
- `preferVisualAbove` falls back to visual-below placement when top-side space is
  insufficient.
- Existing visible-frame clamping behavior remains intact.
- Spotlight clients publish panel state with `preferVisualAbove`; ordinary apps
  publish `automatic`.

## Acceptance

- In Spotlight, KnowType candidates appear above the focused search field instead
  of being hidden by the search results area.
- In ordinary text fields, candidate placement and key behavior remain unchanged.
- `KNOWTYPE_PANEL_DEBUG=1` logs placement preference and final vertical placement.
