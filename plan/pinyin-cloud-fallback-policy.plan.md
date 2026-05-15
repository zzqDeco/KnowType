# Pinyin Cloud Fallback Policy

Goal: allow cloud correction to help with unknown Chinese pinyin composition only when the local engine can identify a pinyin-shaped input but has no local candidate.

Implementation:

- add `PinyinInputAnalysis` to `TraditionalInputEngine`
- report token count, partial-token presence, all-initial-abbreviation shape, local-candidate availability, and likely-pinyin status
- use that analysis in `CorrectionEngine` instead of duplicating pinyin heuristics there
- avoid composing arbitrary single-character candidates from unseeded all-initial inputs
- preserve mixed initial/full-pinyin and initial/technical-token inputs such as `w de fangan` and `w API`
- keep known local abbreviations such as `wsm`, `sm`, and `zmb` local-only
- limit short-input provider fallback to unseeded all-initial abbreviations
- block English-like all-initial words with `y` used as a vowel, such as `why`, `try`, `sync`, `fly`, `sky`, and `gym`
- rank provider candidates ahead of raw identity only for the explicit pinyin-completion fallback path
- protect common technical lowercase tokens such as `css`, `gpt`, `llm`, `npm`, `ssh`, and `sdk`
- keep ordinary English words from triggering pinyin cloud fallback

Validation:

- unknown `wzm` can ask the configured correction provider
- provider correction for unknown pinyin abbreviation can become the first prefix candidate instead of raw `wzm`
- known local abbreviations do not call the provider
- technical tokens and English words do not call the provider
- `swift test --filter TraditionalInputEngineTests`
- `swift test --filter CorrectionEngineTests`
- `swift test`
- `git diff --check`
