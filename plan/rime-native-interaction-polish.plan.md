# Rime Native Interaction Polish

Status: Active

## Summary

KnowType aligns the IMK frontend with mature Rime/Squirrel and Mozc behavior:
keys are handled by the conversion engine first, and the UI renders the engine's
preedit, current-page candidates, and highlighted index. This fixes confusing
state splits where the custom panel or `CompositionBuffer` could disagree with
Rime.

## Scope

- Use Rime preedit as marked text while native composition is active.
- Drive arrow movement, page movement, Space, numbers, and composing symbols
  through the native Rime session before local fallback policy.
- Keep AI recommendation explicit: Tab, Option-number, or mouse click only.
- Keep Return as raw commit and do not change input-source registration,
  appex, release, or `main` workflow.

## Implementation

- Extend the C bridge and Swift conversion boundary with Rime raw input,
  `commit_composition`, and current-page highlight APIs.
- Treat Rime snapshot state as the authoritative current composition:
  partial commits insert committed text and continue showing remaining Rime
  preedit instead of raw pinyin.
- Sync custom candidate-panel selection to Rime highlight. Left/up at the first
  row pages backward and highlights the previous page's last row; right/down at
  the last row pages forward and highlights the next page's first row.
- Route ordinary digits `1...9` to Rime current-page selection whenever native
  composition is active, even if the custom panel is hidden.
- Stop assigning ordinary numeric shortcuts to the AI slot. The visible AI row
  shows Tab when ready; `Option+number` remains explicit.
- Send composing ASCII symbols such as `'`, `;`, and `/` to Rime first. Only
  when Rime declines does KnowType fall back to punctuation conversion; `-`,
  `=`, `,`, and `.` retain Rime-compatible page fallback at page boundaries.

## Test Plan

- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`

Focused coverage includes hidden-panel numeric selection, AI not consuming
ordinary digits, partial Rime commit preedit, symbol-first routing, page-edge
arrow selection, and release-build p95 budgets for arrow/page/number/symbol
hot-path sublinks.

## Assumptions

- Rime is the only production Chinese conversion source.
- AI continuation remains background enhancement and must not block or override
  Space and ordinary number muscle memory.
- Legacy `CompositionBuffer` segment tests remain skipped where they describe
  retired product behavior.
