# CandidatePanelRenderer

`CandidatePanelRenderer` converts `CandidatePanelViewModel` into structured rows for future IMK or SwiftUI presentation code.

The renderer does not draw UI and does not assign colors. It emits semantic roles instead:

- `lockedPrefix` for correction/prefix candidates
- `continuation` for continuation candidates
- `rawInput` for the original input row
- `sectionHeader` for localized grouping labels

Prefix rows and continuation rows are rendered as separate sections. When corrections are present, the raw input row is labeled `0`, prefix shortcuts are numbered `1...n`, and continuation shortcuts use `Tab / Option+1`, `Option+2`, etc.
