# CandidateAnchorResolver

`CandidateAnchorResolver` owns candidate-window geometry resolution for IMK clients.

Current behavior:

- validates candidate anchor rects before the panel consumes them
- accepts zero-width caret rects when height and screen intersection are valid
- normalizes negative-width or negative-height rects before validation
- rejects zero-height, non-finite, and offscreen rects
- resolves anchors in this order: marked end, selected end, marked start, selected start, real-location IMK insertion point, IMK-relative line-height backtracking, Accessibility focused range, scoped last usable anchor
- scopes the last usable anchor to the same composition id, bundle id, screen id, and short age window
- uses `KNOWTYPE_ANCHOR_DEBUG=1` to trace accepted and rejected anchor sources

Accessibility fallback is optional. It only runs when macOS already trusts the process for accessibility access; it does not request permissions during typing.
