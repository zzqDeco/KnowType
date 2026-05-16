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

Selection shortcuts:

- `1...9` commit visible prefix candidates
- `Tab` commits the first continuation for the locked first prefix
- `Option+1...9` commits continuation candidates for the locked first prefix
