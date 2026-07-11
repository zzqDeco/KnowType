# CandidateAnchorResolver

`CandidateAnchorResolver` owns candidate-window geometry resolution for IMK clients.

Current behavior:

- validates candidate anchor rects before the panel consumes them
- accepts zero-width caret rects when height and screen intersection are valid
- normalizes negative-width or negative-height rects before validation
- rejects zero-height, non-finite, and offscreen rects
- resolves anchors in this order: at most four marked/selected `firstRect`
  requests, same-composition/app cache when its current screen is unambiguous,
  at most four strategic IMK-inline line-height requests, throttled
  Accessibility focused range, an otherwise valid deferred multi-screen cache,
  and safe screen fallback
- converts Accessibility bounds with the menu-bar screen top before testing the converted rect against all screens
- clamps marked and selection endpoints to valid IMK inline-session indexes and
  does not perform per-character backtracking
- scopes the last usable anchor to the same composition id, bundle id, screen id, and short age window
- attempts Accessibility at most once per resolve and throttles the same
  composition/app scope for 100 ms from a monotonic timestamp captured at the
  actual Accessibility gate
- uses a stable safe point inside the screen visible frame when host geometry is temporarily unavailable
- uses `KNOWTYPE_ANCHOR_DEBUG=1` to trace accepted and rejected anchor sources
  through `InputDebugDiagnostics`, including probe count, source, composition
  id, bundle id, handled state, and rejection reason without logging raw
  geometry or user text

Accessibility fallback is optional. It only runs when macOS already trusts the process for accessibility access; it does not request permissions during typing.
