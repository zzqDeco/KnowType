# Input Method Native Candidates Fix

Goal: make local macOS testing usable by fixing Chinese composition, caret-following candidate placement, native-feeling candidate UI, and candidate count.

Scope:

- use `IMKTextInput.setMarkedText` while composing, then replace the active marked range on commit
- use the custom AppKit panel as the primary visible candidate surface because `IMKCandidates` can silently fail to appear in some host apps
- recalculate the caret anchor after async suggestion refresh instead of reusing a stale rect
- use marked range end, selected range, line-height rect, and pointer-location fallbacks for candidate anchoring
- show prefix candidates and continuation candidates in one compact native-style list without preview/header chrome
- defer local fallback continuation rows while a configured provider-backed suggestion is pending
- raise default prefix/continuation breadth from 3 to 6 candidates

Validation:

- `swift build`
- `swift test`
- `swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan`
- install the input method bundle and smoke test TextEdit
