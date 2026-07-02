# InputRuntimeBoundaries

## Responsibility

Defines the small value types that keep the IMK runtime split into hot-path
input, candidate-panel presentation, AI slot patches, and background events.
The runtime extractions listed here are current `dev` boundaries, not pending
implementation plans.

## Boundaries

- `InputFrame` and `InputHotPathContext` describe the key-event boundary; the
  hot path should produce marked text, commit commands, panel frame intents, and
  side-effect events without performing disk IO, AI requests, or AppKit panel
  operations directly.
- First-key performance belongs at the existing boundaries: the IMK wrapper may
  schedule a one-time native Rime prewarm after controller initialization, the
  host adapter may delay re-anchor callbacks to avoid same-runloop caret XPC,
  and the coordinator may run cheap AI eligibility before building lexical
  context.
- `CandidatePanelFrame` is the only shape passed to `CandidatePanelPresenter`.
  It carries composition id, raw revision, raw length, anchor source, panel
  model, `CandidatePanelVisibilityReason`, and a presentation generation used
  to order frames across the host/AppKit boundary.
- `InputCompositionStateRuntime` owns pure composition state: raw input,
  `CompositionBuffer`, composition id, raw revision, and delete count. It may
  return snapshots and mutation results, but Rime processing, host writes,
  candidate-panel publication, AI, lexical side effects, and anchor reset stay
  outside this runtime.
- `InputCompositionLifecycleRuntime` owns pure begin and finish lifecycle
  planning. It may map finish reasons, preserve the finishing composition id,
  carry lifecycle commit text, decide owned marked-text clear intent, and own
  first-begin trace-once state, but it must not perform host writes, Rime reset,
  candidate-panel publication, AI/lexical side effects, preference reloads, or
  event publication.
- `InputCandidatePanelPublicationRuntime` owns candidate-panel publication
  state, frame emission, candidate-frame presentation generation, async
  stale-snapshot gating, hide reasons, delayed re-anchor generation, and panel
  diagnostics. It must receive Rime/native facts from the coordinator instead
  of reading the conversion engine.
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
- `InputCommitDecisionRuntime` owns pure commit-choice planning for `Space`,
  `Tab`, `Option-number`, selected rows, AI acceptance, and prefix-learning
  candidate selection. It may return executable plans that ask the coordinator
  to process Rime Space, apply a segment, select a native candidate, or apply an
  `InputCommitResult`, but it must not perform those side effects itself.
- `InputCommitApplicationRuntime` owns commit-result plan mapping, accepted
  feedback context construction, and commit side-effect context construction. It
  returns values only; lifecycle planning, host writes, marked-text cleanup,
  Rime reset, candidate-panel hide, AI/lexical runtime calls, and lifecycle
  event publication remain outside this runtime.
- `InputTurnSequencingRuntime` owns value-only side-effect ordering after a
  commit/native/lifecycle/passthrough decision has already been made. It returns
  ordered effects for panel hide, commit side effects, host insert, post-insert
  verification, Rime reset, composition reset, writer lifecycle finish, and
  runtime-event publication; the coordinator executes those effects.
- `InputTurnSequenceValidator` owns privacy-safe validation of those ordered
  effects. It reports only turn ids, composition ids, raw revisions, effect
  indices, and effect names; it must not inspect user text or execute side
  effects.
- `InputEventBus` records typed lifecycle/commit/selection events for
  background consumers. Publishing an event must not block key handling, and
  retained recent-event history is bounded so the long-running input-method
  process cannot accumulate unbounded memory when no consumer is attached.

## Behavior Notes

- Candidate-panel debug logs are enabled with `KNOWTYPE_PANEL_DEBUG=1` and
  include frame reasons such as `composition_active`, `composition_ended`,
  `layout_impossible`, and `stale_update`; window-layer logs also include
  dropped stale frame generations.
- Candidate-panel publication may hide for raw-empty or stale-suggestion
  snapshots, but anchor source `.none` remains an undisplayable published frame
  so layout-impossible behavior stays diagnosable.
- Candidate-panel visible and hidden updates use one ordered frame channel
  through `InputControllerHost.applyCandidatePanelFrame`; there is no separate
  unordered update/hide host path.
- Production delayed re-anchor callbacks intentionally run after a short delay;
  stale raw/composition gates in `InputCandidatePanelPublicationRuntime` remain
  the correctness boundary that prevents old anchors from reviving the panel.
- Composition state reset must happen only after the coordinator has read any
  commit text and recorded side-effect contexts for the finishing composition.
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
- Commit decision plans are values. Rime conversion, segment mutation,
  candidate-panel publication, accepted-AI tracking, and prefix-learning writes
  remain in the coordinator or their dedicated runtimes.
- Commit side-effect contexts and lifecycle finish plans must be built from the
  finishing composition snapshot before composition state is reset.
- Input turn effect sequences make this ordering explicit for tests; they do
  not replace the coordinator as the owner of IMK/AppKit side effects.
- Turn sequence validation can emit `KNOWTYPE_TURN_DEBUG=1` diagnostics for
  replaying effect order, but it must not fail production input or log user
  content.
- Background consumers may observe events, but they must not call back into the
  active Rime session or AppKit panel.

## Tests

- `InputControllerCoordinatorTests`
- `InputCompositionStateRuntimeTests`
- `InputCompositionLifecycleRuntimeTests`
- `InputCandidatePanelPublicationRuntimeTests`
- `InputNativeCandidateNavigationRuntimeTests`
- `InputLexicalCommitRuntimeTests`
- `InputSuggestionStateRuntimeTests`
- `InputCommitDecisionRuntimeTests`
- `InputCommitApplicationRuntimeTests`
- `InputTurnSequencingRuntimeTests`
- `InputTurnSequenceValidatorTests`
- `InputHotPathPerformanceTests`
- `InputAIRecommendationRuntimeTests`
- `InputRuntimeBoundariesTests`
- `swift test`
