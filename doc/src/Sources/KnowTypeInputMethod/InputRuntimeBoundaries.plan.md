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
- `InputCandidatePanelPublicationRuntime` owns candidate-panel publication
  state, frame emission, async stale-snapshot gating, hide reasons, delayed
  re-anchor generation, and panel diagnostics. It must receive Rime/native
  facts from the coordinator instead of reading the conversion engine.
- `InputNativeCandidateNavigationRuntime` owns Rime/native candidate navigation
  state, panel-selection mapping, stable native index matching, hover
  highlight, numeric current-page selection, paging, and boundary paging. It
  may drive conversion-engine navigation keys, but host writes, commit result
  side effects, and candidate-panel publication stay in the coordinator and
  publication runtime.
- `AIRecommendationPatch` is slot-only. `InputAIRecommendationRuntime` creates
  and validates patches, and they can be applied only when request id, AI
  generation, composition id, raw revision, and raw input still match.
- `InputAIAcceptanceRuntime` owns post-commit AI learning and feedback side
  effects. It receives commit context after the coordinator has chosen the
  inserted text, but it must not perform host writes, Rime updates, or panel
  publication.
- `InputLexicalCommitRuntime` owns local lexical selection and commit side
  effects. It combines protected selection-history recording, bounded recent
  commit tracking, lexical profile refresh scheduling, and commit/selection
  event payload construction without touching host writes, Rime navigation, AI
  providers, or candidate-panel publication.
- `InputSuggestionStateRuntime` owns current suggestion state, its raw-input
  identity, commit suggestion snapshots, and narrow no-provider fallback cleanup.
  It must not call Rime, host clients, AI providers, candidate-panel presenters,
  or runtime preferences.
- `InputEventBus` records typed lifecycle/commit/selection events for
  background consumers. Publishing an event must not block key handling, and
  retained recent-event history is bounded so the long-running input-method
  process cannot accumulate unbounded memory when no consumer is attached.

## Behavior Notes

- Candidate-panel debug logs are enabled with `KNOWTYPE_PANEL_DEBUG=1` and
  include frame reasons such as `composition_active`, `composition_ended`,
  `layout_impossible`, and `stale_update`.
- Candidate-panel publication may hide for raw-empty or stale-suggestion
  snapshots, but anchor source `.none` remains an undisplayable published frame
  so layout-impossible behavior stays diagnosable.
- Native navigation preserves Rime as the source of truth for highlighted and
  current-page candidates. Duplicate native candidate text must match by
  encoded native index before selection; otherwise generic Rime Space remains
  authoritative.
- AI patches must not change Rime selection, marked text, base candidates, or
  panel visibility.
- Lexical commit and selection events are returned to the coordinator for
  asynchronous event-bus publication; lexical refresh can use only bounded
  recent commits and in-process recent selection history.
- Suggestion commit snapshots retain `usesPendingFallback = false`; the retired
  async local-candidate path remains disabled.
- Background consumers may observe events, but they must not call back into the
  active Rime session or AppKit panel.

## Tests

- `InputControllerCoordinatorTests`
- `InputCandidatePanelPublicationRuntimeTests`
- `InputNativeCandidateNavigationRuntimeTests`
- `InputLexicalCommitRuntimeTests`
- `InputSuggestionStateRuntimeTests`
- `InputHotPathPerformanceTests`
- `InputAIRecommendationRuntimeTests`
- `InputRuntimeBoundariesTests`
- `swift test`
