# TraditionalInputEngine

`TraditionalInputEngine` is the clean-room local Chinese input path for KnowType MVP.

- It decodes a license-clean built-in MVP lexicon through pinyin tokenization, compact pinyin segmentation, light typo normalization, and candidate scoring.
- Compact input now uses a pinyin lattice rather than a single hard-coded path, so inputs such as `nishi`, `nishishei`, `xianz`, `niw`, `wsm`, `xiansh`, `zhongguoren`, and `woxiangqukan` can resolve without spaces.
- It supports standalone syllable candidates such as `ni -> 你/尼/呢/...` and trailing partial syllables such as `nih -> 你好` while still keeping `ni` character alternatives in the candidate pool.
- Complete syllables are not split into initial-only partial paths during compact segmentation; `fang` stays a current syllable candidate instead of becoming unrelated phrase fragments.
- It preserves technical and code-like tokens through `TextProtection` instead of forcing them into Chinese.
- Its capitalized-pinyin passthrough is configurable so English-name preservation can remain on for English contexts while `zh-CN` composition can decode sentence-initial pinyin such as `Wo`.
- It exposes a table-driven scheme hook; v1 includes a minimal Xiaohe double-pinyin mapping for the supported smoke tests.
- It returns multiple prefix candidates for ambiguous entries such as `fangan`, so the candidate panel can behave like a traditional input method before AI continuation appears.
- It includes deterministic seed entries for common initial abbreviations such as `sm -> 什么`, `zmb -> 怎么办`, and `wsm -> 为什么`; these remain local engine behavior rather than cloud fallback.
- It routes lexicon lookup through a private `LexiconIndex` that owns exact phrase lookup, duplicate-key merging, length buckets, first-token buckets, known input tokens, max phrase length, and partial-match caps.
- It accepts public `TraditionalInputLexiconEntry` values at initialization time, normalizes their pinyin tokens, ignores malformed empty rows, and folds them into the same private index as the built-in seed lexicon.
- Injected lexicon entries affect both spaced input and compact segmentation because known input tokens are resolved per engine instance.
- It exposes `PinyinInputAnalysis` so correction policy can ask the engine whether an input is pinyin-shaped, already covered locally, or only suitable for provider fallback.
- Recursive parse results are memoized by token index to keep compact sentence input responsive.
