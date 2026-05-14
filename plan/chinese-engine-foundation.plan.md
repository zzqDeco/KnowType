# Chinese Engine Foundation

Goal: make KnowType behave like a usable baseline Chinese input method before layering AI continuation on top.

Implementation:

- expand `TraditionalInputEngine` from seed-example decoding to a pinyin lattice path
- add a complete full-pinyin syllable table and pinyin-prefix table for compact input splitting
- keep a license-clean built-in mini lexicon for MVP tests while leaving room for a larger authorized lexicon importer later
- support common standalone syllables, phrase entries, initial abbreviations, and trailing partial syllables such as `nih`, `niw`, and `xianz`
- memoize recursive parse states so compact pinyin such as `nishishei` stays responsive
- preserve mixed Chinese/English technical-token passthrough
- page candidate rows through `CandidatePanelPagingState` with 9 visible rows per page

Validation:

- `ni -> 你` plus multiple same-pinyin character candidates
- `nih -> 你好` while still keeping `ni` character alternatives in the candidate pool
- `nishi -> 你是`
- `nishishei -> 你是谁`
- `xianz -> 现在`
- `niw -> 你我`
- `wsm -> 为什么`
- `wojuedezhegefagnan -> 我觉得这个方案`
- `swift test --filter TraditionalInputEngineTests`
- `swift test --filter CandidatePanel`
- `swift test`
