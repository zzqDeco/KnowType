# PinyinTables

`PinyinTables.swift` contains the clean-room pinyin metadata used by `TraditionalInputEngine`.

- `pinyinSyllables` is the full-pinyin legal syllable set used for compact input segmentation.
- `pinyinPrefixes` is generated from the syllable table and lets the engine recognize trailing partial input, such as `z` in `xianz`.
- `pinyinInitialTokens` supports initial-abbreviation paths such as `wsm -> 为什么`.

These tables are static metadata. They do not include third-party lexicon data or user phrase history.
