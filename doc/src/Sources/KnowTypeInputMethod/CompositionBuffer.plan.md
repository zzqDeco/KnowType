# CompositionBuffer

`CompositionBuffer` owns the in-progress text model that sits between raw IMK key input and committed text.

Responsibilities:

- keep the original `rawInput` available for Return/Enter raw commit
- store resolved `CandidateSegment` values without allowing overlaps or out-of-bounds ranges
- produce marked-text display by stitching resolved segment text with unresolved raw pinyin
- expose the first unresolved active range for segment candidate lookup
- report when all non-whitespace raw input has been resolved
- support Backspace undo of the latest resolved segment before deleting raw characters

It deliberately does not know about IMK clients, candidate panels, providers, or lexicon ranking. The coordinator owns those integrations and treats this type as a small deterministic composition model.
