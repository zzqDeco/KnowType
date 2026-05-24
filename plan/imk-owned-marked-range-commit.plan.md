# KnowType IMK Owned Marked Range Commit Fix

## Summary

- Fix occasional IMK cursor misplacement where committed text can appear before
  a space, Return, or unrelated nearby text.
- Treat host-reported `markedRange` as advisory geometry only. Ordinary
  composition, commit, and idle passthrough writes use `NSNotFound` replacement
  ranges unless KnowType later owns an explicit reconversion range.

## Scope

- Update `InputControllerCoordinator` write paths for marked text, commit, and
  direct Space/digit passthrough.
- Add privacy-safe `KNOWTYPE_CLIENT_WRITE_DEBUG=1` diagnostics for IMK write
  ranges.
- Update input-method tests and source/interface docs.
- Do not change Rime conversion, AI prompt behavior, candidate panel styling,
  input-source registration, or release flow.

## Implementation

- `insertText` commit writes use an owned replacement range helper that returns
  `NSRange(location: NSNotFound, length: NSNotFound)`.
- `setMarkedText` composition and clear writes use the same `NSNotFound`
  replacement policy so the focused app owns the current composition range.
- Idle Space and idle `0...9` ignore stale host `markedRange` and insert at the
  current cursor.
- Debug logs include write kind, composition id, raw length, selected range,
  reported marked range, chosen replacement range, and reason; they never log
  user text.

## Test Plan

- Stale host `markedRange` must not be used for `ni + Space`, `ni + Return`,
  AI Tab, Option-number AI, idle Space, or idle digits.
- Composition update and cancel clear writes must use `NSNotFound` replacement
  ranges while still updating marked text and hiding the panel.
- Run `swift test --quiet`, `./scripts/smoke-inputmethod-install.sh`,
  `./scripts/perf-input-hotpath.sh`, and `git diff --check`.

## Assumptions

- KnowType does not currently support reconversion or explicit selected-range
  replacement. If that is added later, it must maintain an owned replacement
  range instead of trusting arbitrary host `markedRange`.
