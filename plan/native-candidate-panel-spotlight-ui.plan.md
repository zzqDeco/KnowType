# Native Candidate Panel Spotlight UI

## Summary

- Fix the candidate panel so it stays above Spotlight and system search-like
  overlays without using screen-saver or shielding window levels.
- Tighten the candidate row layout so shortcut labels use measured width instead
  of a fixed reserved slot.
- Keep the Rime-only hot path unchanged; this slice is AppKit presentation only.

## Scope

- Change the native AppKit `NSPanel` configuration for the candidate window.
- Update candidate panel visual metrics, layout measurements, and snapshot
  baselines.
- Add tests for window level and shortcut-slot sizing.
- Do not change input-source registration, Rime conversion, AI recommendation,
  or release packaging.

## Implementation

- Create a `CandidatePanelWindowConfiguration` for the native candidate panel and
  apply it when constructing the `NSPanel`.
- Use `.popUpMenu` window level with `.borderless` and `.nonactivatingPanel`,
  `isFloatingPanel`, `worksWhenModal`, all-spaces/full-screen behavior, and
  `hidesOnDeactivate = false`.
- Replace the old fixed shortcut reserve width with measured
  `shortcutLabelWidth` in `CandidatePanelLayoutItem`.
- Use each row's measured shortcut width for horizontal layout, use the current
  page's maximum shortcut width only for vertical rows that actually have a
  shortcut, and keep rows without shortcut labels free of shortcut spacing.
- Switch native material to `hudWindow`, tighten insets, reduce row height, and
  keep dynamic system colors for selected and disabled rows.

## Test Plan

- `swift test --filter 'CandidatePanel(LayoutEngine|WindowController|Accessibility|Snapshot)Tests'`
- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`
- Manual: install a release build, type in TextEdit/Chrome, then open Spotlight
  and verify the candidate panel is visible above the search field, hover is
  visible, and click commit does not steal focus.

## Assumptions

- Spotlight is treated as the representative system-search overlay.
- `.popUpMenu` is the highest acceptable public AppKit level for this panel.
- Candidate UI should remain compact and system-native, not themeable in this
  slice.
