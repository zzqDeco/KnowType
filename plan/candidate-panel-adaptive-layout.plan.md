# Candidate Panel Adaptive Layout

## Summary

KnowType's candidate panel should measure candidate content before rendering. The current AppKit path lets
`CandidatePanelContentView.fittingSize` and fixed text-width limits decide the panel size after rows are
created, which makes long phrases truncate too early. The adaptive layout work introduces a deterministic
measurement layer that chooses horizontal or vertical layout from row widths, caret position, and visible
screen bounds before the panel is rendered.

## Implementation

- Add `CandidatePanelTextMeasuring` and a production AppKit measurer that uses the same fonts as the panel rows.
- Add `CandidatePanelLayoutEngine` with a small configuration object for row heights, insets, gaps, shortcut
  width, and min/max panel widths.
- Add `CandidatePanelLayoutPlan` containing orientation, panel size, panel origin, per-row frames,
  text width limits, and truncation flags.
- Keep `CandidatePanelRenderer` semantic only: it continues to output rows, selection state, shortcut labels,
  and visual roles.
- Change `CandidatePanelWindowController` to ask the layout engine for size and origin, then pass the plan to
  `CandidatePanelContentView` for rendering.
- Remove fixed candidate text-width limits as the primary sizing mechanism; they become values from the layout
  plan.

## Layout Rules

- Try horizontal layout first with 6 visible candidates, then 5, then 4.
- Adaptive mode caps the effective page size at 6 so a saved 9-row preference does not force vertical layout.
- Use horizontal layout only when at least 4 candidates fit without truncation within
  `220...min(720, availableScreenWidth)`.
- Switch to vertical layout when long phrases would reduce a horizontal row to 1-3 complete candidates.
- Vertical layout uses one candidate per row and grows to `220...min(560, availableScreenWidth)`.
- Preserve row order and shortcut labels across layout changes.
- Clamp the final panel frame to the caret screen's visible frame with a small inset; prefer below the caret and
  flip above when needed.

## Test Plan

- Unit-test short rows choosing horizontal layout for 4-6 candidates.
- Unit-test long rows choosing vertical layout only when 4 complete horizontal candidates cannot fit.
- Unit-test width growth and truncation in vertical layout.
- Unit-test left, right, top, and bottom screen-edge avoidance.
- Update window-controller tests so size and origin come from the layout plan, not `fittingSize`.
- Run `swift test` and `git diff --check`.

## Assumptions

- Long versus short candidate behavior is measurement-based, not character-count based.
- The first implementation does not add visible animation; it only avoids small-width jitter in layout math.
- Code implementation should start from `dev` after PR #72 lands, because the row model is being changed there.
