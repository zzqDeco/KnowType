# InputRuntimeBoundaries

## Responsibility

Defines the small value types that keep the IMK runtime split into hot-path
input, candidate-panel presentation, AI slot patches, and background events.

## Boundaries

- `InputFrame` and `InputHotPathContext` describe the key-event boundary; the
  hot path should produce marked text, commit commands, panel frame intents, and
  side-effect events without performing disk IO, AI requests, or AppKit panel
  operations directly.
- `CandidatePanelFrame` is the only shape passed to `CandidatePanelPresenter`.
  It carries composition id, raw revision, raw length, anchor source, panel
  model, and `CandidatePanelVisibilityReason`.
- `AIRecommendationPatch` is slot-only. It can be applied only when request id,
  AI generation, composition id, raw revision, and raw input still match.
- `InputEventBus` records typed lifecycle/commit/selection events for
  background consumers. Publishing an event must not block key handling, and
  retained recent-event history is bounded so the long-running input-method
  process cannot accumulate unbounded memory when no consumer is attached.

## Behavior Notes

- Candidate-panel debug logs are enabled with `KNOWTYPE_PANEL_DEBUG=1` and
  include frame reasons such as `composition_active`, `composition_ended`,
  `layout_impossible`, and `stale_update`.
- AI patches must not change Rime selection, marked text, base candidates, or
  panel visibility.
- Background consumers may observe events, but they must not call back into the
  active Rime session or AppKit panel.

## Tests

- `InputControllerCoordinatorTests`
- `InputHotPathPerformanceTests`
- `InputRuntimeBoundariesTests`
- `swift test`
