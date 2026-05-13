# CandidatePanelWindowController

`CandidatePanelWindowController` owns the AppKit floating panel used by the macOS input method bundle.

Current behavior:

- renders `CandidatePanelState` through `CandidatePanelRenderer`
- anchors near the IMK client's marked-text end using `IMKTextInput.firstRect`, falls back to selected range, then pointer location when the client does not expose a usable rect
- clamps the panel to the visible frame of the caret's screen
- hides from composition reset, `hidePalettes`, and input-controller close lifecycle
- uses a borderless AppKit floating panel with `NSVisualEffectView` popover material, compact row sizing, full-width blue selected rows, and muted continuation styling to stay close to macOS native input method candidate windows
- avoids preview text, section headers, and raw-input rows once correction candidates are available

Selection shortcuts:

- `1...9` commit visible prefix candidates
- `Tab` commits the first continuation for the locked first prefix
- `Option+1...9` commits continuation candidates for the locked first prefix
