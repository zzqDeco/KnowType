# CandidatePanelWindowController

`CandidatePanelWindowController` owns the candidate panel lifecycle used by the macOS input method bundle.
The default implementation still creates an AppKit floating panel, but the controller now routes rendering,
window operations, sizing, placement, and screen geometry through small internal seams so geometry behavior can
be tested without opening real AppKit windows.

Current behavior:

- renders `CandidatePanelState` through `CandidatePanelRenderer`
- measures and lays out rendered rows through `CandidatePanelLayoutEngine` before touching AppKit views
- updates content through `CandidatePanelContentRendering`; the AppKit implementation consumes `CandidatePanelLayoutPlan`
- creates and drives windows through `CandidatePanelWindowOperating`; the default implementation adapts `NSPanel`
- measures shortcut/text widths through `CandidatePanelTextMeasuring` using the same font choices as rendering
- caches measured text widths and skips identical panel presentations to avoid repeated AppKit layout work during rapid async state updates
- chooses horizontal layout for complete 4-6 candidate rows when they fit, otherwise switches to vertical layout
- computes final panel size, per-row text limits, and the screen-edge-avoiding origin before rendering rows
- consumes the rect chosen by `CandidateAnchorResolver`, including the safe screen fallback when host caret geometry is unavailable
- treats hidden candidate rows as non-selectable so arrow keys and numeric shortcuts do not act on invisible candidates
- clamps the panel to the visible frame of the caret's validated screen, compressing vertical row height and spacing on constrained screens without dropping selectable rows
- resizes the panel before asking the content view to lay out fixed measured row constraints; row containers and labels opt into Auto Layout so candidate text remains visible in real windows
- hides from composition reset, `hidePalettes`, and input-controller close lifecycle
- uses a borderless AppKit floating panel with `NSVisualEffectView` popover material, compact row sizing, full-width blue selected rows, and muted continuation styling to stay close to macOS native input method candidate windows
- avoids preview text, section headers, and raw-input rows once correction candidates are available

Selection shortcuts:

- `1...9` commit visible prefix candidates
- `Tab` commits the first continuation for the locked first prefix
- `Option+1...9` commits continuation candidates for the locked first prefix
