# CandidatePanelWindowController

`CandidatePanelWindowController` owns the fallback AppKit floating panel used by the macOS input method bundle when native `IMKCandidates` cannot be shown.

Current behavior:

- renders `CandidatePanelState` through `CandidatePanelRenderer`
- anchors near the IMK client's selected range using `IMKTextInput.firstRect`
- clamps the panel to the visible frame of the caret's screen
- hides from composition reset, `hidePalettes`, and input-controller close lifecycle
- stays hidden while the native `IMKCandidates` window is active
- uses a borderless AppKit floating panel with `NSVisualEffectView` menu material, compact row sizing, full-width blue selected rows, and muted continuation styling to stay close to macOS native input method candidate windows

Selection shortcuts:

- `0` commits the raw input when correction candidates are visible
- `1...9` commit visible prefix candidates
- `Tab` / `Option+1...9` commit continuation candidates for the locked first prefix
