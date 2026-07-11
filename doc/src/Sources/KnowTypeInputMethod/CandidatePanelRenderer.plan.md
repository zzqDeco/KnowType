# CandidatePanelRenderer

`CandidatePanelRenderer` projects `CandidatePanelRowBuilder` output into
structured render rows for future IMK or SwiftUI presentation code.

The renderer does not draw UI and does not assign colors. It emits semantic roles instead:

- `lockedPrefix` for correction/prefix candidates
- `aiRecommendation` for the fixed AI slot
- `aiPolish` for explicit rewrite status and candidate rows
- `continuation` for continuation candidates
- `rawInput` for the original input row
- `preedit` for commit-only host preedit that cannot be exposed inline
- `symbolCandidate` for panel-backed punctuation choices
- `status` for transient input-mode feedback

Prefix rows, AI rows, and continuation rows remain separate semantic rows, but
the visible fallback panel is a flat native-style strip without section headers
or preview text. Raw input is only exposed while no suggestion is available.
Mode-status and commit-only preedit rows render before candidates. Mode status
is disabled and privacy-safe; commit-only preedit carries the raw/preedit
display text from the coordinator. Neither fixed row has a selection identity or
shortcut.
Row ordering, enabled state, and selection identity come from
`CandidatePanelRowBuilder`; the renderer owns shortcut label strings and
render-row accessibility projection.

Candidate rows are paged through `CandidatePanelPagingState`, with a default adaptive page size of 6 rows so short candidates can remain in a compact horizontal macOS-style panel. Fixed preedit rows do not consume candidate page slots. Vertical-list mode may use up to 9 rows. `CandidatePanelState` owns the active page and moves PageDown/PageUp to the same visible row offset on the target page, clamping on short final pages; arrow navigation advances by one visible row and crosses page boundaries only when the selection moves past a page edge.

The renderer emits only rows from the current visible page. Prefix and symbol
candidate shortcut labels reset to `1...n` for the visible page. Ready AI
recommendations keep the next numeric shortcut, normally `2`; pending,
unavailable, and ineligible AI rows are disabled status rows with no shortcut or
selection identity. Continuation shortcut labels stay tied to their global
commit actions: the first continuation is labeled `⇥`, continuations 2 through 9
are labeled `⌥2...⌥9`, and later continuations have no shortcut label. When a
caller does not pass paging explicitly, the renderer infers the page that
contains the selected row so existing panel update paths continue to show the
selected candidate page.

Each render row carries the `CandidatePanelSelection` used by keyboard/mouse
commit paths, an enabled flag for hit-testing and accessibility, and a concise
accessibility label. Ready AI labels include `AI 推荐`; disabled AI status labels
use `AI 状态`; symbol rows use `符号`; mode-status rows use `输入模式`. Pending AI
render rows keep empty visible text and a spinner accessory, with
`AI 状态，AI 推荐中` supplied explicitly for accessibility.
Ready polish rows use visible numeric shortcuts and `AI 润色` accessibility
labels. They flow through the same pointer and VoiceOver callback as every
other enabled selection, including the AppKit render-generation guard.

Candidate selection is preserved across same-raw-input updates only when the candidate text at the selected index is unchanged. If provider-backed suggestions reorder or replace the row at that index, selection resets to the default first candidate so the highlighted row and commit target never drift apart.
