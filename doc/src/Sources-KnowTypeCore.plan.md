# Sources/KnowTypeCore

`KnowTypeCore` contains the product invariants:

- shared request/response models
- text protection and Level 0 detection
- clean-room traditional pinyin decoding, generated pinyin-resource loading, multi-path compact segmentation, syllable fallback composition, trailing incomplete-syllable completion, compact-prefix completion, typo normalization, and local correction ranking
- prefix-locked continuation sanitization and fallback

Level 0 detection is pure core policy. It covers URLs, emails, file paths, command-like input, code-like tokens, and protected app bundle IDs for Terminal, iTerm2, and Xcode. Level 0 correction returns local identity protection and Level 0 continuation returns no candidates.

Provider-specific protocol details must not be added here.

`TraditionalInputEngine` is intentionally license-clean in MVP. It provides a seed phrase lexicon, a generated CC-CEDICT-derived pinyin resource, broader single-syllable fallback coverage for common input, expanded single-syllable homophone candidates such as `ni -> 你/呢/尼/...`, syllable fallback composition for compact input such as `nishi -> 你是`, common compact phrases such as `zhongguoren -> 中国人` and `nishishei -> 你是谁`, trailing incomplete-syllable completion such as `niw -> 你我` and `nih -> 你好`, multiple candidates for ambiguous pinyin such as `fangan`, compact input support for examples like `wojuedezhegefagnan`, unfinished compact-prefix completion for examples like `xianz -> 现在`, and technical-token passthrough for mixed Chinese/English input.

`CorrectionEngine` gates local traditional pinyin decoding by locale. `en-US` input stays on the English spellcheck path, while `zh-CN` input can decode capitalized pinyin used at the start of a composition.
