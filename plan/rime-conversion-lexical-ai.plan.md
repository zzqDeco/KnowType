# KnowType Rime Conversion And Lexical AI

## Summary

- Move the basic Chinese conversion hot path toward mature IME behavior: indexed local/Rime candidates are available synchronously for `Space` and numeric selection, while AI continuation remains background-only.
- Add an optional native `librime` bridge boundary without requiring Homebrew or checked-in binary artifacts.
- Add a local lexical/tone profile summary for AI continuation requests without uploading full input logs or dictionary databases.

## Scope

- Add `KnowTypeRimeBridge`, a small dynamic C bridge that loads `librime.1.dylib` at runtime and exposes only session setup, key processing, commit/context reads, page changes, and current-page candidate selection.
- Add `RimeConversionEngine` plus a `TraditionalInputEngine` fallback so tests and development remain usable when native Rime artifacts or shared data are absent.
- Keep existing IMK registration, input-source identifiers, appex non-goal, settings UI, and release branch rules unchanged.
- Keep all PR work targeted at `dev`; do not open feature PRs against `main`.

## Implementation

- `InputControllerCoordinator` now publishes indexed local prefix candidates immediately after raw buffer changes, then lets async refresh add slower continuation/AI state.
- `Space` no longer has a pending-async raw fallback branch. It commits the first current candidate or uses the synchronous fallback policy.
- Plain numeric shortcuts read the already-visible candidate snapshot; native Rime sessions can commit via `select_candidate_on_current_page`.
- `AIRecommendationRequest` carries an optional `LexicalContextSnapshot`; `AIRecommendationRuntime` sends it as `LEXICAL_PROFILE.md` and includes its hash in the cache key.
- `scripts/prepare-rime-artifacts.sh` downloads and verifies pinned `librime 1.16.1 / de4700e` macOS universal artifacts into ignored `Vendor/Rime`.
- The prepare script also installs pinned plum recipes for `rime/rime-prelude`
  and `rime/rime-pinyin-simp` shared data by default.
- Native Rime sessions select `pinyin_simp`; the prepared shared data patches
  the schema list to avoid missing-schema deploy noise.
- `scripts/build-inputmethod-bundle.sh` copies optional Rime dylibs/plugins/shared data into the app bundle before signing.

## Test Plan

- `swift test`
- `./scripts/smoke-inputmethod-install.sh`
- `git diff --check`
- Manual IME acceptance: fast `ni` + `Space` commits `你`; fast numeric selection commits candidate rows without appending digits; AI rows appear only after the basic candidate path is already usable.

## Assumptions

- Native Rime is optional in source-tree runs unless explicitly enabled; bundled
  release apps use prepared artifacts automatically.
- Full user dictionary export remains follow-up work.
- AI receives only top-K lexical/tone summaries, not complete DB files or full raw input history.
