# InputAIPolishRuntime

## Responsibility

`InputAIPolishRuntime` owns explicit IMK polish gating, provider dispatch,
request identity, overlay state, stale-result rejection, and acceptance lease
validation.

## Boundaries

- It reuses `ProviderRuntimeRegistry.shared` through
  `InputAIPolishProviderRuntime` and sends `LLMRequest(task: .polish)`.
- It does not call continuation prompt/runtime code or
  `PrefixContinuationEngine` sanitization.
- It does not write marked text, insert host text, mutate Rime, render AppKit,
  or record learning. The coordinator owns those side effects.

## Behavior Notes

- The strict polish gate requires an active nonempty composition and rejects
  protected-app, Level 0, and secret-like text before provider leasing.
- Pending, ready, and unavailable state carries request/composition/revision
  identity plus provider generation when known.
- Provider completion and explicit acceptance both revalidate current identity;
  acceptance also validates the provider lease before returning a candidate.
- Provider revision notifications cancel pending or ready state immediately;
  acceptance validation remains the fallback for missed notifications.
- Reset cancels request and acceptance tasks and clears all candidate state;
  mode shortcuts cancel the overlay before their normal action runs.
- The runtime emits request, ready, unavailable, cancellation, acceptance, and
  stale-drop diagnostics using identifiers, lengths, counts, and normalized
  reasons only. It stores no raw text and emits no provider output to logs.

## Tests

- `InputAIPolishRuntimeTests`
- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
- `swift test`
