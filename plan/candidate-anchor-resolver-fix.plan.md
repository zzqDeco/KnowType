# Candidate Anchor Resolver Fix

Goal: make candidate positioning resilient to delayed, stale, or malicious host
geometry without allowing synchronous probes to grow with composition length.

This Wave 2 slice covers only the anchor-budget portion of issue #184. Host
shortcut cleanup, accessibility press handling, and scroll-gesture paging are
dependent PR 9 work and are not part of this change.

Implementation:

- move anchor lookup out of `InputController` into `CandidateAnchorResolver`
- validate rects before use, allowing zero-width caret rects, normalizing negative-size rects, and rejecting zero-height/offscreen geometry
- try at most four deduplicated marked/selected `firstRect` ranges
- after invalid `firstRect` results, reuse an unexpired last usable anchor only
  when composition id, app bundle id, and screen identity still match
- replace per-character line-height backtracking with at most four deduplicated
  IMK-inline strategic positions: marked end, in-range selection end, marked
  start, and zero
- resolve Accessibility at most once per resolver call and throttle repeated
  attempts for the same composition/app scope for 100 ms, then use a stable
  safe point inside the visible screen frame
- convert Accessibility bounds from the menu-bar screen top before screen containment checks, so vertically arranged displays above the primary screen stay addressable
- scope last usable anchors by composition id, bundle id, screen id, and age so old input fields do not move the panel
- re-anchor once on the next main run loop after `setMarkedText` when the same composition is still active
- remove mouse pointer fallback from the candidate panel controller; if host geometry is unavailable, use the safe screen fallback rather than leaving invisible candidates selectable
- expose `KNOWTYPE_ANCHOR_DEBUG=1` trace output with probe count, source, and
  rejection reason; never include user text or raw geometry

Validation:

- `swift test --filter CandidateAnchor`
- `swift test --filter InputDebugDiagnosticsTests`
- `swift test --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`
- local Apple Development install smoke test in TextEdit and Chrome
