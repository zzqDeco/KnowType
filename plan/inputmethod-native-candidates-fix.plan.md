# Input Method Native Candidates Fix

Goal: make local macOS testing usable by fixing Chinese composition, caret-following candidate placement, native-feeling candidate UI, and candidate count.

Scope:

- use `IMKTextInput.setMarkedText` while composing, then replace the active marked range on commit
- use `IMKCandidates` as the primary candidate surface when available
- fall back to the custom AppKit panel only if native candidates cannot be created
- recalculate the caret anchor after async suggestion refresh instead of reusing a stale rect
- use selected range, marked range, and line-height rect fallbacks for candidate anchoring
- show prefix candidates and continuation candidates in the native candidate list
- raise default prefix/continuation breadth from 3 to 6 candidates

Validation:

- `swift build`
- `swift test`
- `swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan`
- install the input method bundle and smoke test TextEdit
