# Pinyin Prefix Completion Fix

## Problem

The first pinyin-initial fix covered high-frequency shortcuts such as `wsm -> 为什么`, but unfinished compact pinyin such as `xianz` could still fail before candidate generation because tokenization required a complete syllable path.

## Changes

- Add compact-prefix completion over known lexicon entries so unfinished input can still produce local candidates, for example `xianz -> 现在` and `xiansh -> 显示`.
- Keep exact pinyin candidates ahead of longer prefix completions, so `xian` still prefers `先` while exposing longer options as candidates.
- Treat compact-prefix input as provider-eligible correction input when a provider is configured.
- Cap provider confidence for pinyin composition corrections below strong local candidates so cloud results expand coverage without replacing solid local decoding.

## Validation

- `swift test --filter TraditionalInputEngineTests`
- `swift test --filter CorrectionEngineTests`
- `swift test`
