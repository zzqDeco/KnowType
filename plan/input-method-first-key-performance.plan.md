# KnowType Input Method First-Key Performance

## Summary

- Status: Active.
- Branch: `fix/input-method-first-key-performance`.
- Goal: reduce the one-time IMK first-key stall after install or process cold
  start without changing Rime behavior, candidate ranking, host compatibility,
  AI provider output, or installer scripts.
- This slice targets the measured cold path: native Rime session creation,
  same-runloop IMK caret re-anchoring, unnecessary AI lexical context work on
  skipped requests, and repeated hot-path regular-expression compilation.

## Scope

- Keep `RimeConversionEngine` lazy for normal read-only construction, but allow
  `KnowTypeInputController` to schedule one background native-session prewarm
  after controller initialization.
- Delay production IMK re-anchor callbacks by a small amount so first key
  handling does not synchronously re-enter host caret geometry in the same
  runloop.
- Add a cheap AI scheduling gate before building lexical profile and accepted
  feedback context for paths that are too short, disabled, or have no provider.
- Cache privacy/protection regular expressions used by `TextProtection` and
  lexical profile sanitization.

Non-goals:

- Do not add a new cold-start runtime object.
- Do not change Rime schema deployment, installation, repair, host carrier
  policy, Settings UI, AI prompts, or candidate ordering.
- Do not run local install, repair, or uninstall scripts from this branch.

## Implementation

- `InputMethodRimePrewarmer` schedules a process-wide `Task.detached` prewarm
  from `KnowTypeInputController.init`. The prewarm creates and releases a
  temporary `NativeRimeSession`; if the user's first key arrives before prewarm
  completes, the existing synchronous lazy path remains authoritative.
- Native-session prewarm is best-effort. Session creation serializes the
  process-global librime bridge initialization state, but the speculative
  prewarm path uses a try-lock and skips when foreground creation is already in
  progress.
- `RimeConversionEngine.prewarmNativeSession(configuration:)` emits
  `KNOWTYPE_STARTUP_DEBUG=1` timing for start/done events and logs schema and
  success state without logging user text.
- `IMKInputControllerHostAdapter.scheduleDelayedReanchor` uses a short
  `asyncAfter` delay while retaining the existing raw/composition stale gates
  inside the candidate-panel publication runtime.
- Post-insert AI feedback caret verification uses a separate next-main-queue
  seam so quick Delete feedback is not delayed by candidate-panel re-anchor
  throttling.
- `InputControllerCoordinator.scheduleAIRecommendation` evaluates a lightweight
  `InputAIRecommendationSchedulePolicy` context first. Only schedule-eligible
  requests build lexical context and accepted-feedback snapshots.
- Regular expressions in `TextProtection` and `LexicalContextBuilder`
  sanitization paths are static cached objects.

## Test Plan

- `swift test --quiet --filter RimeConversionEngineTests`
- `swift test --quiet --filter InputAIRecommendationRuntimeTests`
- `swift test --quiet --filter InputControllerCoordinatorTests`
- `swift test --quiet --filter CorrectionEngineTests`
- `swift test --quiet --filter InputCandidatePanelPublicationRuntimeTests`
- `swift test --quiet --filter InputHotPathPerformanceTests`
- `swift test`
- `git diff --check`

Manual acceptance after merge should install the branch build, enable
`KNOWTYPE_STARTUP_DEBUG=1` and `KNOWTYPE_INPUT_LATENCY_DEBUG=1`, kill the input
method app, switch back to KnowType, wait briefly, and type the first character
in TextEdit, Chrome, and Codex. Expected behavior is no mouse beachball during
ordinary first-key input and startup logs showing Rime prewarm completion or a
shortened first native session create path.

## Assumptions

- The one-time visible stall is dominated by cold Rime/dyld/IMK host geometry
  work. Lexical context construction is still worth gating because it adds
  repeated hot-path cost, but it alone does not explain a one-time stall.
- Background prewarm may create Rime runtime directories as a consequence of
  initializing a native session after the controller is live. Install-time and
  host prelaunch read-only guarantees remain covered by the earlier cold-start
  no-user-data-write plan because this branch does not move prewarm into
  install or registration scripts.
