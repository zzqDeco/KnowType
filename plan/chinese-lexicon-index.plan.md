# Chinese Lexicon Index

Goal: prepare `TraditionalInputEngine` for a larger authorized Chinese lexicon without changing the current user-visible candidate behavior.

Implementation:

- keep the current clean-room seed lexicon and pinyin lattice
- add a private `LexiconIndex` for exact lookup, length buckets, first-token buckets, known input tokens, and max phrase length
- merge duplicate pinyin keys inside the index while keeping the highest confidence per output text
- route partial-syllable matching through indexed candidate buckets instead of filtering the entire lexicon
- cap partial-match expansion so broad prefixes do not flood parse states when the lexicon grows
- preserve existing behaviors for compact pinyin, spaced pinyin, initial abbreviations, technical-token passthrough, and candidate ranking

Validation:

- `sm`, `zmb`, and `wsm` still decode as compact initial abbreviations
- `s m`, `z m b`, and `w s m` decode through the same indexed partial path
- trailing partial inputs such as `xian z` still resolve correctly
- `swift test --filter TraditionalInputEngineTests`
- `swift test`
- `git diff --check`
