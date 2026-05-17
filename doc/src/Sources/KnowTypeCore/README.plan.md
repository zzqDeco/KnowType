# Sources/KnowTypeCore

`KnowTypeCore` contains the product invariants:

- shared request/response models
- shared input-mode preference models and runtime state for punctuation language and symbol width
- text protection and Level 0 detection
- clean-room traditional pinyin decoding, compact segmentation, typo normalization, and local correction ranking
- prefix-locked continuation sanitization and fallback

Level 0 detection is pure core policy. It covers URLs, emails, file paths, command-like input, code-like tokens, and protected app bundle IDs for Terminal, iTerm2, and Xcode. Level 0 correction returns local identity protection and Level 0 continuation returns no candidates.

`PrefixContinuationEngine` uses deterministic local fallback continuations only when no provider is configured. Once a provider is present, continuation candidates must come from that provider and pass prefix-lock sanitization; provider failures or unusable provider responses return no continuations so the input method keeps showing traditional prefix candidates rather than mock AI text.

Provider-specific protocol details must not be added here.

`TraditionalInputEngine` is still license-clean in MVP, but it now uses a full-pinyin syllable table, pinyin-prefix recognition, memoized lattice parsing, indexed lexicon lookup, and a bundled TSV smoke-test lexicon loaded through `TraditionalInputSeedLexicon`. It provides multiple same-pinyin single-character candidates for inputs such as `ni`, phrase candidates for inputs such as `nishishei`, partial-syllable handling for inputs such as `nih`, `niw`, and `xianz`, and technical-token passthrough for mixed Chinese/English input.

Managed dictionary growth stays explicit and license-aware. `ManagedLexiconPackInstaller` can install the recommended Rime Pinyin Simplified pack by downloading a pinned Apache-2.0 source, verifying its checksum, converting it into KnowType TSV, and writing local metadata beside the installed resource.

`CorrectionEngine` gates local traditional pinyin decoding by locale. `en-US` input stays on the English spellcheck path, while `zh-CN` input can decode capitalized pinyin used at the start of a composition. Provider fallback for short Chinese input is driven by `PinyinInputAnalysis`: known local pinyin candidates stay local, but unknown all-initial abbreviations may ask the configured correction provider. Recent `InputContext.userSelectionHistory` can boost already-generated prefix candidates, but it does not create candidates or leave the local process.
