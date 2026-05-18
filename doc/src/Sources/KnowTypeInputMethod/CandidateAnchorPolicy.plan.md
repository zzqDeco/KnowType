# CandidateAnchorPolicy

## Responsibility

`CandidateAnchorPolicy` defines the range choices used when resolving candidate
panel geometry from IMK clients.

## Boundaries

- Geometry probing and fallback ordering stay in `CandidateAnchorResolver`.
- AppKit window positioning stays in `CandidatePanelWindowController`.

## Behavior Notes

- The policy chooses marked, selected, insertion-point, and line-height ranges
  without assuming every host app reports complete IMK geometry.
- It supports safe fallback behavior for browsers and Electron-style clients
  where marked-text ranges can lag behind key handling.

## Tests

- `CandidateAnchorPolicyTests`
- `CandidateAnchorResolverTests`
