# CandidatePanelWindowController

`CandidatePanelWindowController` owns the candidate panel lifecycle used by the macOS input method bundle.
The default implementation still creates an AppKit floating panel, but the controller now routes rendering,
window operations, sizing, placement, and screen geometry through small internal seams so geometry behavior can
be tested without opening real AppKit windows.

Current behavior:

- renders `CandidatePanelState` through `CandidatePanelRenderer`
- updates content through `CandidatePanelContentRendering`; the AppKit implementation is `CandidatePanelContentView`
- creates and drives windows through `CandidatePanelWindowOperating`; the default implementation adapts `NSPanel`
- constrains measured content through `CandidatePanelWindowSizing` before applying the window size
- computes origins through `CandidatePanelWindowPlacement` using injected `ScreenGeometryProviding`
- consumes the rect chosen by `CandidateAnchorResolver`; if no usable rect is available, it hides/skips display until a valid anchor arrives
- treats hidden candidate rows as non-selectable so arrow keys and numeric shortcuts do not act on invisible candidates
- clamps the panel to the visible frame of the caret's validated screen, including the tolerance used by `ScreenGeometryProviding.screen(containing:)`
- hides from composition reset, `hidePalettes`, and input-controller close lifecycle
- uses a borderless AppKit floating panel with `NSVisualEffectView` popover material, compact row sizing, full-width blue selected rows, and muted continuation styling to stay close to macOS native input method candidate windows
- avoids preview text, section headers, and raw-input rows once correction candidates are available

Planned adaptive layout:

- introduce `CandidatePanelLayoutEngine` as the measurement-first layer between renderer and AppKit view
- measure shortcut and text widths using the same fonts as rendered rows before deciding panel size
- prefer horizontal layout for 4-6 complete candidates and switch to vertical layout when long phrases would force horizontal truncation below 4 complete candidates
- compute the final panel size and screen-edge-avoiding origin before rendering rows
- pass per-row frames and text width limits to `CandidatePanelContentView` instead of relying on fixed text-width constants or `fittingSize` as the source of truth

Selection shortcuts:

- `1...9` commit visible prefix candidates
- `Tab` commits the first continuation for the locked first prefix
- `Option+1...9` commits continuation candidates for the locked first prefix
