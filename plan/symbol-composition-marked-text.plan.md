# Symbol Composition Marked-Text Preview

## Summary

- Present the selected ambiguous symbol as a real input composition before
  commit.
- Keep inline marked text, commit-only placeholder hosts, the custom candidate
  panel, and the single `SymbolComposition` selection synchronized.

## Scope

- Extend symbol sessions with privacy-safe presentation revision, carrier, and
  post-write host range snapshots.
- Reuse `InputClientCompositionWriter` for inline symbol marked text and the
  existing U+3000 commit-only placeholder.
- Complete commit, cancel, focus, shortcut, printable replay, delayed anchor,
  mouse, and accessibility lifecycle behavior.
- Do not change symbol rules, candidate ordering, Rime, AI, Provider contracts,
  locked-prefix behavior, persistence, or recognized event masks.

## Implementation

- The active-session runtime accepts presentation acknowledgements only for the
  current symbol composition id, revision, and host identity. Focus lifecycle
  compares against the latest successful post-write snapshot rather than the
  pre-mark snapshot.
- Marked-text ownership is keyed by client identity and composition id. A stale
  session cannot clear a newer composition, and missing or changed clients
  release local ownership without writing to the wrong host.
- Inline hosts receive the selected symbol as attributed marked text.
  Commit-only hosts receive the existing placeholder and expose the selected
  symbol in the panel preedit row.
- Selection changes rewrite the same owned mark. Clamped navigation remains
  handled but does not rewrite an unchanged revision.
- Commit clears the matching mark and inserts exactly one symbol. Cancel clears
  without insertion. Printable fallthrough commits once and replays once.
- Initial presentation failure cancels the session and returns the trigger to
  the host when possible. Later presentation failure consumes the current
  symbol event and removes the hidden session and panel.
- `composedString()` exposes the selected symbol, `originalString()` is empty
  for symbol sessions, and the controller intercepts parameterless IMK cancel
  only while a symbol session is active.

## Test Plan

- Cover presentation acknowledgement freshness, host snapshots, carrier
  selection, owned-mark identity, inline/placeholder writes, and stale cleanup.
- Cover keyboard, responder command, repeated trigger, paging, hover, mouse,
  accessibility, commit, cancel, shortcut, focus, generation, failure, replay,
  and delayed re-anchor paths.
- Run focused session, writer, coordinator, panel, and key-mapper tests, then
  `swift test`, `./scripts/perf-input-hotpath.sh`, and `git diff --check`.
- Build an installable version for user-run TextEdit, Chrome/Electron,
  VS Code/Codex, Terminal, horizontal/vertical panel, mouse, and VoiceOver
  acceptance.

## Assumptions

- The custom candidate panel remains the symbol-candidate authority.
- Commit-only hosts keep the existing U+3000 placeholder.
- Navigation stays clamped rather than wrapping.
- Issue #208 closes after automated gates and user host-app acceptance.
