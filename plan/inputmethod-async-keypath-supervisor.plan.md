# Input Method Async Keypath Supervisor

Delivered on `fix/inputmethod-async-keypath-supervisor`.

## Summary

KnowType's IMK key path now prioritizes immediate marked-text feedback. Key handling updates the raw
composition and schedules background work; local candidate generation, AI recommendation, panel rendering,
runtime lexicon refresh, and context-memory logging are cancellable asynchronous tasks.

## Key Changes

- Added `InputTaskSupervisor` as the shared cancellation registry for
  cancellable input work; the later Rime-only path retired the old local
  candidate generation model.
- Changed async suggestion refresh so `append`/`delete` publish raw marked text first and compute local candidates off the synchronous key path.
- Coalesced candidate panel updates and delayed re-anchor work so rapid typing cancels stale layout/anchor tasks.
- Moved AI recommendation, runtime lexicon refresh, and context event logging onto background/utility tasks.
- Removed synchronous local fallback from pending `Space`, `Tab`, and punctuation paths; pending commits use current visible raw/composition text.
- Cached candidate panel text measurements and skipped identical panel presentations.

## Test Coverage

- `swift test`
- `git diff --check`
- Updated `InputControllerCoordinatorTests` for immediate raw feedback, deferred candidate publication, AI pending behavior, and no provider correction on the key path.
