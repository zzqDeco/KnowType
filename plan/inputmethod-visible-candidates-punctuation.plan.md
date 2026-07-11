# Input Method Visible Candidates And Punctuation

## Summary

This fix aligns punctuation defaults, candidate visibility, and commit behavior for the macOS input method.

## Behavior

- Input mode is process-global for the input-method host. Legacy `codeAppState`
  preference data remains readable for migration but does not select runtime
  punctuation mode.
- `Option + .` updates the process-global Chinese/English punctuation mode and
  synchronizes the active native Rime session.
- The async input path publishes raw marked text and an immediate local prefix-only candidate snapshot. It does not publish hidden local fallback continuations while a provider-backed continuation request is pending.
- `Space` commits only the current visible candidate snapshot for the current raw input. If only raw input is visible, `Space` must not commit a hidden Chinese fallback.
- `Return` / `Enter` still commits the raw composition.
- Provider-backed continuation rows remain asynchronous and are shown only after provider output is usable.
- Candidate anchoring falls back from IMK geometry, line-height geometry, Accessibility, and scoped last usable anchors to a stable safe point inside the screen visible frame. Pointer location is not used as a moving fallback.
- AppKit candidate rows keep explicit Auto Layout participation so row text remains visible in real windows after measured layout is applied.

## Regression Scope

Compact pinyin examples such as `wsm` are regression scenarios for visibility/commit consistency only. They do not define a hard-coded first-candidate rule. If the local engine returns Chinese prefix candidates, the panel must show them before `Space` can commit one. If the visible row is only raw input, `Space` commits raw input.

## Verification

```bash
swift test --filter InputControllerCoordinator
swift test --filter InputSymbolMode
swift test --filter CandidateAnchor
swift test --filter CandidatePanel
swift test
git diff --check
```
