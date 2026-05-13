# CandidatePanelRenderer

`CandidatePanelRenderer` converts `CandidatePanelViewModel` into structured rows for future IMK or SwiftUI presentation code.

The renderer does not draw UI and does not assign colors. It emits semantic roles instead:

- `lockedPrefix` for correction/prefix candidates
- `continuation` for continuation candidates
- `rawInput` for the original input row
- `sectionHeader` for localized grouping labels

Prefix rows and continuation rows are rendered as separate sections for fallback/custom presentation. The native candidate list receives prefix rows first and continuation rows after them; raw input is only exposed as a native row while no suggestion is available. Fallback labels keep `0` for raw input, `1...n` for prefix shortcuts, and compact macOS-style continuation labels such as `Tab  ⌥1`, `⌥2`, etc.
