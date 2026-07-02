# InputAIRecommendationRuntime

## Responsibility

`InputAIRecommendationRuntime` owns the IMK-side lifecycle for real-time AI
recommendation requests.

It builds `AIRecommendationRequest` values from coordinator-provided input
context, records privacy-safe diagnostics, tracks the active request id and
generation, owns the input-method trailing debounce before transport dispatch,
and publishes matching `AIRecommendationState` updates back to the coordinator.

## Boundaries

- It may call the injected `AIRecommendationProviding` runtime.
- It may record `AIRecommendationDiagnosticEvent` values.
- It may read the provider-availability snapshot for no-provider fallback
  decisions.
- It exposes `shouldBuildRecommendationContext` so the coordinator can skip
  expensive lexical and accepted-feedback snapshots after a lazy provider is
  known unavailable, while still building context for actual recommendation
  runtimes in the unknown/available states.
- It exposes `shouldScheduleRecommendationRequest` separately from the heavy
  context gate. Scheduling remains tied to an actual
  `AIRecommendationProviding`; legacy eager-provider flags only suppress
  fallback rows through `hasKnownProvider`. Lazy providers remain schedulable
  for a lightweight availability probe after a known-unavailable state, so
  Settings changes can be discovered without restarting the IMK process.
- It must not access host clients, marked text, candidate-panel presentation,
  Rime selection, commit/write paths, or settings persistence.

## Behavior Notes

- Scheduling starts with `InputAIRecommendationSchedulePolicy`; skipped states
  do not start provider tasks.
- IMK callers use an input-method trailing debounce before dispatching the
  provider request. During that debounce the runtime keeps state `.idle`, so the
  candidate panel does not flash a pending AI row while the user is still
  typing.
- New input cancels only the pre-dispatch debounce task. Once transport has
  started, the runtime does not abort the provider task; it invalidates the old
  request id/generation and lets the old result return through the existing
  stale-drop path.
- Known-unavailable lazy providers run availability probes without lexical or
  accepted-feedback context. A probe returns `.idle` synchronously and suppresses
  unavailable async results, but still applies a recovered `.ready` result.
- `hasKnownProvider` remains scoped to suppressing no-provider fallback rows; it
  is not the heavy-context construction gate.
- Provider requests never include real-time Rime candidate hints.
- Async results apply only when request id, generation, composition id, raw
  revision, and raw input still match the current composition snapshot.
- Reset and reschedule paths preserve existing `cancel_previous`,
  `stale_result_dropped`, and `state_applied` diagnostic semantics, and add
  `dispatch_deferred`, `dispatch_cancelled_by_new_input`, `transport_started`,
  and `transport_left_stale` for request-timing analysis. Set
  `KNOWTYPE_AI_DEBUG=1` or `KNOWTYPE_PERF_DEBUG=1` to mirror privacy-safe AI
  diagnostics to stderr/unified logging without raw input, candidates, locked
  prefixes, provider output, or context bodies.
- AI diagnostic elapsed fields separate debounce wait from provider transport
  time: `transport_started` reports time since scheduling, and returned,
  stale-dropped, or applied transport results report elapsed provider time.

## Tests

- `InputAIRecommendationRuntimeTests`
- `InputAIRecommendationSchedulePolicyTests`
- `InputControllerCoordinatorTests`
- `swift test`
