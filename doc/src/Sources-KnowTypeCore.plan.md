# Sources/KnowTypeCore

`KnowTypeCore` contains the product invariants:

- shared request/response models
- text protection and Level 0 detection
- clean-room traditional pinyin decoding, compact segmentation, syllable fallback composition, compact-prefix completion, typo normalization, and local correction ranking
- prefix-locked continuation sanitization and fallback

Level 0 detection is pure core policy. It covers URLs, emails, file paths, command-like input, code-like tokens, and protected app bundle IDs for Terminal, iTerm2, and Xcode. Level 0 correction returns local identity protection and Level 0 continuation returns no candidates.

Provider-specific protocol details must not be added here.

`TraditionalInputEngine` is intentionally small in MVP. It provides a license-clean seed lexicon, syllable fallback composition for basic compact input such as `nishi -> 你是`, multiple candidates for ambiguous pinyin such as `fangan`, compact input support for examples like `wojuedezhegefagnan`, unfinished compact-prefix completion for examples like `xianz -> 现在`, and technical-token passthrough for mixed Chinese/English input.

`CorrectionEngine` gates local traditional pinyin decoding by locale. `en-US` input stays on the English spellcheck path, while `zh-CN` input can decode capitalized pinyin used at the start of a composition.
