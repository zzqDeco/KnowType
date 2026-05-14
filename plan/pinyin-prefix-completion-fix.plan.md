# Pinyin Prefix Completion Fix

## Problem

The first pinyin-initial fix covered high-frequency shortcuts such as `wsm -> 为什么`, but unfinished compact pinyin such as `xianz` could still fail before candidate generation because tokenization required a complete syllable path.

## Changes

- Add compact-prefix completion over known lexicon entries so unfinished input can still produce local candidates, for example `xianz -> 现在` and `xiansh -> 显示`.
- Add syllable fallback composition so basic compact input does not require a whole phrase entry, for example `nishi -> 你是`.
- Use multi-path compact pinyin segmentation instead of a single greedy path, so common continuous input can keep producing candidates instead of stalling.
- Add a generated CC-CEDICT-derived pinyin resource and runtime pinyin index instead of relying on the Swift seed table for broad coverage.
- Expand the clean-room fallback table with common syllables and short phrases, for example `zhongguoren -> 中国人`, `keyi -> 可以`, `meiyou -> 没有`, and `nishishei -> 你是谁`.
- Expand single-syllable homophone candidates so `ni` exposes enough candidates for candidate-window paging.
- Complete a trailing unfinished syllable in compact input, for example `niw -> 你我` and `nih -> 你好`, while keeping completed-prefix candidates available for inputs such as `nih`.
- Page the candidate panel in native-style 9-item slices; number keys select candidates from the current page.
- Support common pagination keys `PageUp` / `PageDown`, `-` / `=`, and `[` / `]`.
- Keep exact pinyin candidates ahead of longer prefix completions, so `xian` still prefers `先` while exposing longer options as candidates.
- Keep the highest-confidence duplicate candidate path so phrase and compact-prefix candidates are not demoted by lower-confidence fallback parses.
- Prefer IMK text rects, line-height rects, the current insertion-point range, and the last usable text anchor for the candidate window; do not use the mouse pointer as the moving anchor.
- Do not show fallback/mock AI continuations in the immediate local input path; continuation rows appear only when real provider output is available or the caller explicitly asks for fallback continuations.
- Treat compact-prefix input as provider-eligible correction input when a provider is configured.
- Cap provider confidence for pinyin composition corrections below strong local candidates so cloud results expand coverage without replacing solid local decoding.

## Validation

- `swift test --filter TraditionalInputEngineTests`
- `swift test --filter CorrectionEngineTests`
- `swift test`
