# CandidateAnchorResolver

`CandidateAnchorResolver` owns candidate-window geometry resolution for IMK clients.

Current behavior:

- validates candidate anchor rects before the panel consumes them
- accepts zero-width caret rects when height and screen intersection are valid
- normalizes negative-width or negative-height rects before validation
- rejects zero-height, non-finite, and offscreen rects
- resolves anchors in this order: marked end, selected end, marked start, selected start, real-location IMK insertion point, IMK-relative line-height backtracking, Accessibility focused range, scoped last usable anchor, safe screen fallback
- converts Accessibility bounds with the menu-bar screen top before testing the converted rect against all screens
- line-height backtracking uses IMK inline-session character indexes and clamps marked-range end positions to the last valid inline character
- scopes the last usable anchor to the same composition id, bundle id, screen id, and short age window
- uses a stable safe point inside the screen visible frame when host geometry is temporarily unavailable
- uses `KNOWTYPE_ANCHOR_DEBUG=1` to trace accepted and rejected anchor sources
  through `InputDebugDiagnostics`, including source, composition id, bundle id,
  handled state, and rejection reason without logging raw geometry

Accessibility fallback is optional. It only runs when macOS already trusts the process for accessibility access; it does not request permissions during typing.
