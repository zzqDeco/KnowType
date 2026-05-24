# KnowType Input Runtime Boundaries Refactor

## Summary

- Establish hard runtime boundaries between Rime key handling, candidate panel presentation, AI recommendation, and Rime userdb maintenance.
- Fix the class of regressions where background lexical/profile work can perturb the active IMK composition or make the candidate panel disappear after repeated commits.
- Keep all work on `refactor/input-runtime-boundaries` with PR base `dev`; this slice does not touch `main`, release packaging, input-source registration, or appex exploration.

## Scope

- Add input-runtime boundary types for hot-path frames, candidate-panel frames, typed runtime events, and AI recommendation patches.
- Introduce `CandidatePanelPresenter` so the coordinator emits panel frames with explicit visibility reasons instead of directly driving AppKit for every update.
- Introduce `RimeMaintenanceService` and split Rime userdb reads into existing-snapshot reads versus explicit sync reads.
- Introduce `LexicalProfileRuntime` so profile refresh, userdb parsing, persistent profile writes, and related diagnostics are no longer expanded inside `InputControllerCoordinator`.
- Keep `InputControllerCoordinator` as the IMK glue layer for now, while moving side-effect boundaries out of its direct AppKit/Rime-maintenance calls.
- Preserve existing Rime-only behavior for Space, digits, arrows, paging, symbols, direct passthrough, AI slot updates, and lexical profile persistence.

## Implementation

- `InputRuntimeBoundaries.swift` defines:
  - `InputHotPathContext` / `InputFrame` for key-event frame boundaries.
  - `CandidatePanelFrame` and `CandidatePanelVisibilityReason` for panel update/hide intents.
  - `InputEventBus` and `InputRuntimeEvent` for commit/selection/lifecycle side effects.
  - `AIRecommendationPatch` for generation-checked AI slot updates.
- `CandidatePanelPresenter` consumes `CandidatePanelFrame`, updates or hides through `InputControllerHost`, and emits `KNOWTYPE_PANEL_DEBUG=1` logs with reason, composition id, raw revision, raw length, anchor source, and layout state.
- `RimeUserDBTextSnapshotProvider.userDBTextSnapshot` now reads an already exported `*.userdb.txt` snapshot only. `syncedUserDBTextSnapshot` is the explicit sync path.
- `RimeMaintenanceService` owns explicit sync policy. Commit/selection profile refresh uses the existing-snapshot path; `sync_user_data` is reserved for manual/idle maintenance follow-up.
- `LexicalProfileRuntime` owns delayed lexical refresh, Rime userdb snapshot parsing, profile store staging/publish, request-local lexical context merging, and AI diagnostic logging for profile refresh.
- `InputControllerCoordinator` now:
  - routes panel updates through `CandidatePanelPresenter`;
  - records typed runtime events for composition start/end, commit, and candidate selection;
  - applies AI state only through `AIRecommendationPatch` matching request id, generation, composition id, raw revision, and raw input;
  - keeps transient empty Rime snapshots from hiding the panel while raw input is still active, falling back to a raw/preedit candidate frame.

## Test Plan

- Unit tests:
  - Rime userdb snapshot provider reads existing snapshots without calling sync.
  - Explicit synced snapshot calls `syncUserData`.
  - Plain keydown does not request Rime userdb snapshots.
  - Commit-triggered lexical refresh uses the active Rime schema id without calling `sync_user_data` from the coordinator.
  - Transient empty native snapshots with non-empty raw input keep a raw fallback panel frame visible.
  - Source-level hot-path guard rejects `syncUserData` / `syncedUserDBTextSnapshot` inside `InputControllerCoordinator`.
- Required validation:
  - `swift test --quiet`
  - `./scripts/smoke-inputmethod-install.sh`
  - `./scripts/perf-input-hotpath.sh`
  - `git diff --check`

## Assumptions

- Rime base conversion remains the only production Chinese conversion path.
- AI recommendation, lexical profile persistence, and userdb maintenance failures must not hide the candidate panel or block Space/number/page hot paths.
- This slice establishes boundaries and stops the highest-risk cross-effects; a future cleanup can further shrink `InputControllerCoordinator` once these seams are stable under review.
