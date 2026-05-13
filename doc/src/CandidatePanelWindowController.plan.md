# CandidatePanelWindowController

`CandidatePanelWindowController` owns the AppKit floating panel used by the macOS input method bundle.

Current behavior:

- renders `CandidatePanelState` through `CandidatePanelRenderer`
- anchors near the IMK client's selected range using `IMKTextInput.firstRect`
- clamps the panel to the visible frame of the caret's screen
- hides from composition reset, `hidePalettes`, and input-controller close lifecycle
- keeps raw/prefix selection on the custom panel so the native `IMKCandidates` window is not shown at the same time

Selection shortcuts:

- `0` commits the raw input when correction candidates are visible
- `1...9` commit visible prefix candidates
- `Tab` / `Option+1...9` commit continuation candidates for the locked first prefix
