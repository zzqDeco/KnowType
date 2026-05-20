# Rime-Only Hot Path Performance

Status: Active

## Summary

KnowType retires the production IMK dependency on the clean-room
`TraditionalInputEngine` for base Chinese conversion. `librime` is the only
synchronous conversion source for marked text, Space commit, number selection,
and candidate paging.

## Key Decisions

- `RimeConversionEngine` no longer falls back to `TraditionalInputEngine`.
- The IMK product controller no longer initializes `InputMethodLexiconRuntime`
  or builds a `TraditionalInputEngine` during startup.
- Rime-unavailable sessions expose raw input with no candidates and let the
  coordinator keep raw commit usable.
- The native bridge copies only the current Rime menu page on the key path.
- Numeric selection uses `select_candidate_on_current_page`.
- AI recommendation and lexical context remain background work and cannot block
  Space or number selection.
- The retired local segment-selection, sync fallback continuation, and runtime
  lexicon reload coordinator tests are skipped with an explicit retirement
  reason instead of being silently repurposed.

## Validation

- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`

`scripts/perf-input-hotpath.sh` runs release-build strict p50/p95/max checks for
Rime and coordinator sublinks, and also fails if the coordinator references the
retired local conversion hot-path calls.
