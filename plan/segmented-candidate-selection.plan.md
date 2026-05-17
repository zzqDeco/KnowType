# Segmented Candidate Selection

## Summary

KnowType now treats candidate rows as edits over raw input spans instead of plain text replacements. This brings the input method closer to mature macOS Chinese IME behavior:

- marked text initially shows raw pinyin while candidates are still unconfirmed
- candidates carry the raw range they cover
- selecting a segment updates the active composition only
- `Return` commits the original raw buffer
- `Space` commits a full candidate, or applies the selected segment and commits only after the composition is fully resolved

AI continuation remains gated behind a stable locked prefix. Half-resolved pinyin composition does not trigger continuation.

## Delivered Scope

- Added `TextRange` and `CandidateSegment` to the core candidate model.
- Extended `CorrectionCandidate` and `TraditionalInputCandidate` with raw ranges and segment metadata.
- Updated `TraditionalInputEngine` tokenization and parse state so each output segment records the raw span it covers.
- Added `segmentCandidates(for:activeRange:)` for local segment candidates such as `nishishei -> 你 / 你是 / 你是谁`.
- Added `CompositionBuffer` to keep `rawBuffer`, resolved segment state, active range, display text, and commit text separate.
- Updated the input-method coordinator so marked text uses composition display text instead of eagerly replacing raw pinyin with the first Chinese candidate.
- Added full-candidate and segment-candidate selection kinds for candidate panel and native candidate lists.
- Changed Return/Enter to `commitRaw`.
- Prioritized segment candidates near the front of the candidate list while retaining additional full candidates for paging.

## Behavior

Example flow:

```text
type nishishei
marked text: nishishei
candidates: 你是谁, 你是, 你, ...

select 你
marked text: 你shishei
no committed text yet

select 是谁 or continue by segment
marked text: 你是谁

Space
commit: 你是谁

Return at any point
commit: nishishei
```

`Backspace` first removes the latest resolved segment. If no segment is resolved, it deletes raw input characters.

## Follow-Ups

- Add arbitrary caret-position segment editing.
- Add richer segment highlighting in marked text when the host supports attributed marked text reliably.
- Tune ranking once larger managed lexicons expose more phrase alternatives.
