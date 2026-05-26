# CandidatePanelWindowController

`CandidatePanelWindowController` owns the candidate panel lifecycle used by the macOS input method bundle.
The default implementation creates an AppKit non-activating popup-level panel, and the controller routes rendering,
window operations, sizing, placement, and screen geometry through small internal seams so geometry behavior can
be tested without opening real AppKit windows.

Current behavior:

- renders `CandidatePanelState` through `CandidatePanelRenderer`
- measures and lays out rendered rows through `CandidatePanelLayoutEngine` before touching AppKit views
- updates content through `CandidatePanelContentRendering`; the AppKit implementation consumes `CandidatePanelLayoutPlan`
- creates and drives windows through `CandidatePanelWindowOperating`; the default implementation adapts `NSPanel`
- measures shortcut/text widths through `CandidatePanelTextMeasuring` using the same font choices as rendering
- centralizes candidate-panel visual metrics in `CandidatePanelAppearance`
- caches measured text widths and skips identical panel presentations to avoid repeated AppKit layout work during rapid async state updates
- chooses horizontal layout for complete 4-6 candidate rows when they fit, otherwise switches to vertical layout
- computes final panel size, per-row text limits, visual-above/visual-below placement, and the screen-edge-avoiding origin before rendering rows
- consumes the rect chosen by `CandidateAnchorResolver`, including the safe screen fallback when host caret geometry is unavailable
- treats hidden candidate rows as non-selectable so arrow keys and numeric shortcuts do not act on invisible candidates
- clamps the panel to the visible frame of the caret's validated screen, compressing vertical row height and spacing on constrained screens without dropping selectable rows
- resizes the panel before asking the content view to lay out fixed measured row constraints; row containers and labels opt into Auto Layout so candidate text remains visible in real windows
- hides from composition reset, `hidePalettes`, and input-controller close lifecycle
- uses a borderless non-activating AppKit panel at `.popUpMenu` window level, with all-spaces/full-screen auxiliary behavior, `isFloatingPanel`, `worksWhenModal`, and `hidesOnDeactivate = false`
- uses `NSVisualEffectView` `hudWindow` material, compact row sizing, system highlight selection, 0.5 pt separator border, continuous corners, and muted continuation/AI-status styling to stay close to macOS native input method candidate windows
- uses placement preference rather than elevated private window levels to keep Spotlight candidates above the search results overlay; ordinary apps keep automatic visual-below placement
- hit-tests visible rows so hover updates selection, mouse up commits the same selection as keyboard shortcuts, and disabled AI status rows do not react
- maps scroll-wheel up/down to PageUp/PageDown with a threshold so trackpad jitter does not page accidentally
- exposes each visible row as an accessibility element; enabled candidates use button semantics, disabled AI status uses static-text semantics, and selection changes post focused-element and selected-children notifications
- avoids preview text, section headers, and raw-input rows once correction candidates are available

Selection shortcuts:

- `1...9` commit visible prefix candidates
- `Tab` commits the first continuation for the locked first prefix
- `Option+1...9` commits continuation candidates for the locked first prefix

Screenshot QA:

- `CandidatePanelSnapshotTests` renders fixed AppKit examples for light horizontal, dark vertical, and AI-status layouts.
- Baselines are stored in `Tests/KnowTypeInputMethodTests/__Snapshots__/`.
- `KNOWTYPE_RECORD_SNAPSHOTS=1` refreshes baselines; default test runs compare PNG output and write actual/diff files only under a temporary directory on mismatch.
- `KNOWTYPE_PANEL_DEBUG=1` logs placement preference and final vertical placement with the layout trace.
