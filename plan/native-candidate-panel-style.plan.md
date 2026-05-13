# Native Candidate Panel Style

Goal: make the KnowType candidate panel feel closer to macOS native input method candidate windows without changing prefix-locking behavior.

Scope:

- keep raw input, locked prefix, and continuation candidates as separate semantic data paths
- actively show the custom AppKit panel instead of relying on `IMKCandidates`, because the system panel can silently fail to appear in some text clients
- anchor to the marked-text/caret rect when available, then selected range, then pointer location
- use compact full-width candidate rows with native selected-row coloring and no preview/header chrome
- shorten visible shortcut labels to macOS glyph style such as `⇥` and `⌥2`
- defer local fallback continuation rows while a provider-backed result is pending, so configured AI does not look like fixed mock text
- preserve `Space`, `Tab`, `Option+number`, and `Option+R` behavior
- show up to six local prefix/continuation candidates before paging or provider results

Validation:

- `swift test`
- local input method install and TextEdit smoke test when InputMethodKit can be exercised manually
