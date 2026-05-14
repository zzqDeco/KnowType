# TraditionalInputEngine

`TraditionalInputEngine` is the clean-room local Chinese input path for KnowType MVP.

- It decodes a license-clean seed lexicon and generated CC-CEDICT-derived pinyin resource through pinyin tokenization, multi-path compact pinyin segmentation, light typo normalization, syllable fallback composition, compact-prefix completion, and candidate scoring.
- The generated resource is stored at `Sources/KnowTypeCore/Resources/pinyin_lexicon.tsv` and can be rebuilt with `scripts/build-cedict-pinyin-lexicon.py`; attribution is tracked in `Sources/KnowTypeCore/Resources/NOTICE-CC-CEDICT.md`.
- Phrase entries still rank above syllable fallback composition, but fallback syllables keep basic input such as `nishi -> 你是` working even when no phrase entry exists.
- The fallback table and resource index cover common daily and product-development syllables so compact input can compose phrases such as `zhongguoren -> 中国人`, `keyi -> 可以`, `meiyou -> 没有`, and `nishishei -> 你是谁` instead of failing when a phrase entry is missing.
- Single-syllable fallback entries may emit expanded homophone lists, for example `ni -> 你/呢/尼/...`, so the candidate panel can page through more than the first few items.
- Compact segmentation may complete a trailing unfinished syllable, for example `niw -> 你我` and `nih -> 你好`; it also keeps completed-prefix candidates such as `你/呢/尼/...` available when the next syllable is only partially typed.
- It includes a small high-frequency pinyin-initial abbreviation layer for MVP cases such as `wsm -> 为什么`, plus generic prefix completion over known compact entries for unfinished input such as `xianz -> 现在`.
- Duplicate candidates keep the highest confidence path, so strong compact-prefix or phrase candidates are not demoted by lower-confidence syllable parses.
- Resource outputs are indexed by pinyin token arrays and capped per parse step so broad lexicon coverage does not explode candidate search.
- It still allows provider-backed correction to improve or expand short ambiguous abbreviation and compact-prefix inputs.
- It preserves technical and code-like tokens through `TextProtection` instead of forcing them into Chinese.
- Its capitalized-pinyin passthrough is configurable so English-name preservation can remain on for English contexts while `zh-CN` composition can decode sentence-initial pinyin such as `Wo`.
- It exposes a table-driven scheme hook; v1 includes a minimal Xiaohe double-pinyin mapping for the supported smoke tests.
- It returns multiple prefix candidates for ambiguous entries such as `fangan`, so the candidate panel can behave like a traditional input method before AI continuation appears.
