# CandidatePanelRenderer

`CandidatePanelRenderer` converts `CandidatePanelViewModel` into structured rows for future IMK or SwiftUI presentation code.

The renderer does not draw UI and does not assign colors. It emits semantic roles instead:

- `lockedPrefix` for correction/prefix candidates
- `continuation` for continuation candidates
- `rawInput` for the original input row
- `sectionHeader` remains available for future grouped presentations but is not emitted by the native-style input panel renderer

Prefix rows and continuation rows remain separate semantic rows, but the visible fallback panel is a flat native-style list without section headers or preview text. Raw input is only exposed while no suggestion is available. Labels keep `1...n` for prefix shortcuts and compact macOS-style continuation labels such as `⇥`, `⌥2`, etc.
