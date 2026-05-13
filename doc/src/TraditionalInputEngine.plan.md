# TraditionalInputEngine

`TraditionalInputEngine` is the clean-room local Chinese input path for KnowType MVP.

- It decodes a small license-clean seed lexicon through pinyin tokenization, compact pinyin segmentation, light typo normalization, and candidate scoring.
- It includes a small high-frequency pinyin-initial abbreviation layer for MVP cases such as `wsm -> 为什么`, while still allowing provider-backed correction to improve or expand these short ambiguous inputs.
- It preserves technical and code-like tokens through `TextProtection` instead of forcing them into Chinese.
- Its capitalized-pinyin passthrough is configurable so English-name preservation can remain on for English contexts while `zh-CN` composition can decode sentence-initial pinyin such as `Wo`.
- It exposes a table-driven scheme hook; v1 includes a minimal Xiaohe double-pinyin mapping for the supported smoke tests.
- It returns multiple prefix candidates for ambiguous entries such as `fangan`, so the candidate panel can behave like a traditional input method before AI continuation appears.
