# Native Candidate Panel Style

Goal: make the KnowType candidate panel feel closer to macOS native input method candidate windows without changing prefix-locking behavior.

Scope:

- keep raw input, locked prefix, and continuation candidates as separate semantic sections
- replace the flat custom background with AppKit popover vibrancy
- use compact full-width candidate rows with native selected-row coloring
- shorten visible shortcut labels to macOS glyph style
- preserve `Space`, `Tab`, `Option+number`, and `Option+R` behavior

Validation:

- `swift test`
- local input method install and TextEdit smoke test when InputMethodKit can be exercised manually
