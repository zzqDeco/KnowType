# Candidate Anchor Resolver Fix

Goal: make the candidate panel positioning behave like a mature macOS input method frontend, especially in Chromium and Electron clients where IMK caret geometry can be delayed or stale.

Implementation:

- move anchor lookup out of `InputController` into `CandidateAnchorResolver`
- validate rects before use, allowing zero-width caret rects, normalizing negative-size rects, and rejecting zero-height/offscreen geometry
- try IMK first-rect ranges, real-location IMK insertion point, IMK-relative line-height backtracking, Accessibility focused-range bounds, then scoped last usable anchor
- convert Accessibility bounds from the menu-bar screen top before screen containment checks, so vertically arranged displays above the primary screen stay addressable
- line-height fallback uses IMK inline-session indexes and never probes one past the marked text
- scope last usable anchors by composition id, bundle id, screen id, and age so old input fields do not move the panel
- re-anchor once on the next main run loop after `setMarkedText` when the same composition is still active
- remove mouse pointer fallback from the candidate panel controller and hide/skip display when no valid anchor exists, without leaving invisible candidates selectable
- expose `KNOWTYPE_ANCHOR_DEBUG=1` trace output for local diagnosis

Validation:

- `swift test --filter CandidateAnchor`
- `swift test`
- local Apple Development install smoke test in TextEdit and Chrome
