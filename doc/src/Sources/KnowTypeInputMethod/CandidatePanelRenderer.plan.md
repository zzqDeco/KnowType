# CandidatePanelRenderer

`CandidatePanelRenderer` converts `CandidatePanelViewModel` into structured rows for future IMK or SwiftUI presentation code.

The renderer does not draw UI and does not assign colors. It emits semantic roles instead:

- `lockedPrefix` for correction/prefix candidates
- `continuation` for continuation candidates
- `rawInput` for the original input row
Prefix rows and continuation rows remain separate semantic rows, but the visible fallback panel is a flat native-style strip without section headers or preview text. Raw input is only exposed while no suggestion is available.

Candidate rows are paged through `CandidatePanelPagingState`, with a default adaptive page size of 6 rows so short candidates can remain in a compact horizontal macOS-style panel. Vertical-list mode may use up to 9 rows. `CandidatePanelState` owns the active page and moves PageDown/PageUp to the same visible row offset on the target page, clamping on short final pages; arrow navigation advances by one visible row and crosses page boundaries only when the selection moves past a page edge.

The renderer emits only rows from the current visible page. Prefix shortcut labels reset to `1...n` for the visible page. Continuation shortcut labels stay tied to their global commit actions: the first continuation is labeled `⇥`, continuations 2 through 9 are labeled `⌥2...⌥9`, and later continuations have no shortcut label. When a caller does not pass paging explicitly, the renderer infers the page that contains the selected row so existing panel update paths continue to show the selected candidate page.

Candidate selection is preserved across same-raw-input updates only when the candidate text at the selected index is unchanged. If provider-backed suggestions reorder or replace the row at that index, selection resets to the default first candidate so the highlighted row and commit target never drift apart.
