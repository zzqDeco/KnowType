# Pinyin Prefix Completion Fix

## Problem

The first pinyin-initial fix covered high-frequency shortcuts such as `wsm -> 为什么`, but unfinished compact pinyin such as `xianz` could still fail before candidate generation because tokenization required a complete syllable path.

## Changes

- Add compact-prefix completion over known lexicon entries so unfinished input can still produce local candidates, for example `xianz -> 现在` and `xiansh -> 显示`.
- Add syllable fallback composition so basic compact input does not require a whole phrase entry, for example `nishi -> 你是`.
- Expand single-syllable homophone candidates so `ni` exposes enough candidates for candidate-window paging.
- Complete a trailing unfinished syllable in compact input, for example `niw -> 你我`, while keeping completed-prefix candidates available for inputs such as `nih`.
- Page the candidate panel in native-style 9-item slices; number keys select candidates from the current page.
- Keep exact pinyin candidates ahead of longer prefix completions, so `xian` still prefers `先` while exposing longer options as candidates.
- Treat compact-prefix input as provider-eligible correction input when a provider is configured.
- Cap provider confidence for pinyin composition corrections below strong local candidates so cloud results expand coverage without replacing solid local decoding.

## Validation

- `swift test --filter TraditionalInputEngineTests`
- `swift test --filter CorrectionEngineTests`
- `swift test`
