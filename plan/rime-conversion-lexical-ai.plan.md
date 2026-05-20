# KnowType Rime Conversion And Lexical AI

## Summary

- Move the basic Chinese conversion hot path toward mature IME behavior: indexed local/Rime candidates are available synchronously for `Space` and numeric selection, while AI continuation remains background-only.
- Add an optional native `librime` bridge boundary without requiring Homebrew or checked-in binary artifacts.
- Add a local lexical/tone profile summary for AI continuation requests without uploading full input logs or dictionary databases.

## Scope

- Add `KnowTypeRimeBridge`, a small dynamic C bridge that loads `librime.1.dylib` at runtime and exposes only session setup, key processing, commit/context reads, page changes, full-list candidate iteration, and candidate selection.
- Add `RimeConversionEngine` plus a `TraditionalInputEngine` fallback so tests and development remain usable when native Rime artifacts or shared data are absent.
- Keep existing IMK registration, input-source identifiers, appex non-goal, settings UI, and release branch rules unchanged.
- Keep all PR work targeted at `dev`; do not open feature PRs against `main`.

## Implementation

- `InputControllerCoordinator` now publishes indexed local prefix candidates immediately after raw buffer changes, then lets async refresh add slower continuation/AI state.
- `Space` no longer has a pending-async raw fallback branch. It commits the first current candidate or uses the synchronous fallback policy.
- Plain numeric shortcuts read the already-visible candidate snapshot; native Rime sessions commit by stable `select_candidate` index so locally paged rows and duplicate text preserve Rime learning/state.
- `AIRecommendationRequest` carries an optional `LexicalContextSnapshot`; `AIRecommendationRuntime` sends it as `LEXICAL_PROFILE.md` and includes its hash in the cache key.
- `scripts/prepare-rime-artifacts.sh` downloads and verifies pinned `librime 1.16.1 / de4700e` macOS universal artifacts into ignored `Vendor/Rime`.
- The prepare script also installs pinned plum recipes for `rime/rime-prelude`
  and `rime/rime-pinyin-simp` shared data by default.
- Native Rime sessions select `pinyin_simp`; the prepared shared data patches
  the schema list to avoid missing-schema deploy noise.
- Native Rime key handling treats `handled == true` without commit text as a
  consumed in-session action, so local fallback cannot prematurely commit text.
- Explicit segment-candidate `Space` selection is handled before native Rime
  `Space`, and native numeric full-candidate selection maps by current context
  candidate text to avoid augmented-list index drift.
- Explicit continuation selection also runs before native Rime `Space`, native
  suggestions preserve local offline continuations when no provider is
  configured, and protected app commits/selections are excluded from lexical
  profile history before any later AI recommendation request.
- Fully resolved compositions commit before native `Space`, runtime conversion
  engine reloads replay active raw input into the replacement session, and
  duplicate native candidate text maps by encoded stable native index.
- Native snapshots now read the complete Rime candidate list through
  `candidate_list_begin` / `candidate_list_next` when available. Space on a
  non-highlighted custom-panel prefix/full row selects that stable native index
  before the generic Rime Space path, while non-ASCII composition text bypasses
  native Rime until reset to keep raw-buffer state consistent.
- Current-page snapshot fallback stores global candidate indices, shared-data
  recipe repositories are pinned by exact commit, and `KnowTypeInputMethodApp`
  is linked with the Rime Frameworks rpath instead of patching the executable
  during packaging.
- Synchronous native/local candidate publication cancels stale async local
  refresh tasks before publishing, and Delete-to-empty resets the conversion
  engine so non-ASCII fallback bypasses do not leak into the next composition.
- The C bridge requires the stdbool librime API and the artifact script
  re-checks cached plum data against the pinned ref each run. Versioned Rime API
  tail calls check `data_size` before reading optional function pointers.
- `scripts/build-inputmethod-bundle.sh` copies optional Rime dylibs/plugins/shared data into the app bundle before signing and fails packaging if the required Rime rpath is missing.

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
