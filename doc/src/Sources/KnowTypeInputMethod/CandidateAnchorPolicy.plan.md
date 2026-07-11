# CandidateAnchorPolicy

## Responsibility

`CandidateAnchorPolicy` defines the range choices used when resolving candidate
panel geometry from IMK clients.

## Boundaries

- Geometry probing and fallback ordering stay in `CandidateAnchorResolver`.
- AppKit window positioning stays in `CandidatePanelWindowController`.

## Behavior Notes

- The policy emits at most four deduplicated marked/selected `firstRect`
  requests.
- Line-height requests are limited to at most four deduplicated IMK-inline
  strategic positions: marked end, in-range selection end, marked start, and
  zero. It never performs per-character backtracking.
- It supports safe fallback behavior for browsers and Electron-style clients
  where marked-text ranges can lag behind key handling.

## Tests

- `CandidateAnchorPolicyTests`
- `CandidateAnchorResolverTests`
