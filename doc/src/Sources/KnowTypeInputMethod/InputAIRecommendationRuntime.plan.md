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
  provider request. Eligible inputs return `.pending` immediately so the
  candidate panel keeps a fixed AI placeholder row while waiting for stable
  input. Provider-availability probes and skip paths still return `.idle` or
  their explicit ineligible/unavailable state instead of showing a placeholder.
- New input cancels only the pre-dispatch debounce task before the provider is
  called. Once transport has started, the runtime invalidates the old request
  id/generation, keeps the transport tracked, and stores only the latest
  trailing revision; any late result still has to pass the stale-drop gate
  before it can affect UI.
- Known-unavailable lazy providers run availability probes without lexical or
  accepted-feedback context. A probe returns `.idle` synchronously and suppresses
  unavailable async results, but still applies a recovered `.ready` result.
- `hasKnownProvider` remains scoped to suppressing no-provider fallback rows; it
  is not the heavy-context construction gate.
- Provider requests never include real-time Rime candidate hints.
- Async results apply only when request id, generation, composition id, raw
  revision, and raw input still match the current composition snapshot.
- Provider-registry `.stale` is consumed as a control result: when the request is
  still active and owns a normal pending placeholder, it clears the request and
  publishes `.idle`. A stale older request cannot clear a newer request, and an
  availability probe does not publish a redundant state callback.
- Reset and reschedule paths preserve existing `cancel_previous`,
  `stale_result_dropped`, and `state_applied` diagnostic semantics, and add
  `pending_placeholder`, `dispatch_deferred`,
  `dispatch_cancelled_by_new_input`, `transport_started`, and
  `transport_left_stale` for request-timing analysis. Set
  `KNOWTYPE_AI_DEBUG=1` or `KNOWTYPE_PERF_DEBUG=1` to mirror privacy-safe AI
  diagnostics to stderr/unified logging without raw input, candidates, locked
  prefixes, provider output, or context bodies.
- AI diagnostic elapsed fields separate debounce wait from provider transport
  time: `transport_started` reports time since scheduling, and returned,
  stale-dropped, or applied transport results report elapsed provider time.
- Started transport remains a gate-owned provider operation; continued typing
  produces at most one trailing dispatch, and stale completion is dropped
  without provider-failure accounting. `Reset` and `close` discard UI and
  trailing state while the real transport remains tracked to completion or hard
  timeout.

## Tests

- `InputAIRecommendationRuntimeTests`
- `InputAIRecommendationSchedulePolicyTests`
- `InputControllerCoordinatorTests`
- `swift test`
