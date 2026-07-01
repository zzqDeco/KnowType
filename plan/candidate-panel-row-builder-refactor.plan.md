# Candidate Panel Row Builder Refactor

## Summary

Move candidate-panel row ordering into `CandidatePanelRowBuilder` so
`CandidatePanelState` and `CandidatePanelRenderer` consume the same row model.

This is a small refactor aimed at reducing selection/display drift. It should
not change visible candidate behavior, shortcut labels, paging, or commit
semantics.

## Scope

- Add `CandidatePanelRowBuilder`, `CandidatePanelRowItem`, and
  `CandidatePanelRowList`.
- Use the builder from `CandidatePanelState` for default selection, keyboard
  navigation rows, paging rows, and visible number-shortcut eligibility.
- Use the builder from `CandidatePanelRenderer` for fixed preedit rows and
  pageable display rows.
- Keep renderer-owned shortcut labels and accessibility render-row projection.
- Add focused builder tests and keep existing state/renderer behavior tests
  passing.

Non-goals:

- Do not change candidate panel layout, AppKit drawing, AI generation, Rime
  candidate publication, or host compatibility behavior.
- Do not split `InputControllerCoordinator` in this slice.

## Implementation

- Build fixed rows separately from pageable rows so preedit rows still do not
  consume candidate page slots.
- Derive prefix, full-candidate, and segment-candidate selection identity in
  the builder.
- Mark only prefix/full/segment rows as number-shortcut eligible.
- Treat disabled AI status rows as visible but not selectable.
- Update source notes and indexes in the same PR.

## Test Plan

- `swift test --quiet --filter CandidatePanelRowBuilderTests`
- `swift test --quiet --filter CandidatePanelRendererTests`
- `swift test --quiet --filter CandidatePanelStateTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test`
- `git diff --check`

## Assumptions

- Current row ordering is the intended behavior and should be preserved.
- Candidate row ordering belongs below state and renderer, while shortcut label
  strings remain renderer-owned.
