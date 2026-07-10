# InputControllerCoordinator

`InputControllerCoordinator` owns the testable state machine behind `KnowTypeInputController`.
After the input-runtime refactor sequence, it is primarily the IMK side-effect
ordering owner: dedicated runtimes return state, plans, or contexts, while the
coordinator still executes Rime, host write, panel, AI, lexical, lifecycle, and
event publication side effects in the required order.

Current behavior:

- maps `InputKeyStroke` values through `InputKeyCommandMapper`
- delegates raw input, `CompositionBuffer`, composition id, raw revision, and
  delete-count state to `InputCompositionStateRuntime`
- delegates composition begin and finish lifecycle planning to
  `InputCompositionLifecycleRuntime`, including first-begin trace-once state,
  lifecycle reason to panel reason mapping, finished composition id capture,
  lifecycle commit text carrying, and owned marked-text clear intent
- reads process-wide input-mode snapshots, compares their generation on every
  turn, synchronizes native Rime options, and resets coordinator-local quote
  fallback and symbol-candidate state
  when another session changed the mode; stale symbol overlays are restored to
  composition UI or hidden before the current key continues
- selects a host compatibility write mode before writing or passing through
  printable input through `InputClientCompositionWriter`
- writes marked text through `InputControllerClient.setMarkedText`; inline hosts
  receive Rime preedit as attributed marked text, while terminal-style or
  override commit-only hosts receive a full-width-space `NSAttributedString`
  placeholder with marked attributes that keeps IMK composition ownership
  without exposing raw pinyin
- sends the real raw/preedit display text to the candidate-panel view model for
  commit-only hosts only, so placeholder hosts show preedit above candidates
  without writing it into the host text field while inline hosts avoid duplicate
  preedit rows
- commits through `InputControllerClient.insertText` with a centralized write
  stack; normal composition, commit, and direct passthrough writes use
  `NSNotFound` and do not trust stale host `markedRange`
- treats host `markedRange` as advisory geometry/diagnostic state only; future reconversion must introduce an explicit owned range before replacing existing text
- tracks KnowType-owned marked text by client and clears only that owned mark;
  `InputClientCompositionWriter` owns the tracked client id and clear-before-
  insert ordering, while idle Return/Enter returns to the host without clearing
  stale host marked ranges
- maps Return/Enter to raw commit; retired local segment selection is no longer generated on the production IMK path
- publishes raw marked text and current-page Rime candidates synchronously
- reads composition snapshots from `InputCompositionStateRuntime` when building
  write state, AI request context, candidate-panel publication snapshots, and
  commit/selection learning context
- delegates current suggestion storage, raw-input freshness checks, commit
  suggestion snapshots, and no-provider fallback continuation cleanup to
  `InputSuggestionStateRuntime`
- delegates candidate-panel state publication, async refresh coalescing,
  visibility decisions, delayed re-anchor generation, and panel diagnostics to
  `InputCandidatePanelPublicationRuntime`
- delegates Rime/native candidate selection state, panel-selection mapping,
  hover highlight, numeric current-page selection, paging, and boundary paging
  decisions to `InputNativeCandidateNavigationRuntime`
- supplies candidate-panel publication context: raw input, composition id, raw
  revision, suggestion snapshots, preferred native highlight, AI slot state,
  placement preference, preedit display text, and resolved anchor facts
- keeps `Space` tied to Rime's highlighted/current candidate for the current raw input; while Rime handles composition without commit, the key is consumed and the marked text refreshes
- passes idle printable ASCII back to compatibility hosts when no composition is
  active; native candidate-only snapshots still count as active composition for
  number selection
- maps Option+/ to the shared Chinese/ASCII transition, which also restores
  linked Chinese/English punctuation; app bundle changes do not reload mode
- maps Option+. to a Chinese-mode-only manual punctuation override; ASCII mode
  keeps English punctuation and only republishes status
- keeps Shift+Space width changes independent, transforms idle printable ASCII
  and space when required, and propagates saved global-width changes through the
  shared runtime generation
- keeps AI recommendation explicit: Tab, Option-number, and mouse click can commit a ready AI row, but ordinary digits are reserved for Rime candidates
- when native Rime is active, hover and arrow selection go through
  `InputNativeCandidateNavigationRuntime` so Rime's current-page highlight stays
  authoritative instead of making the custom panel selection authoritative on
  its own
- explicit native `PageUp`/`PageDown` are forwarded through
  `InputNativeCandidateNavigationRuntime` while composition is active,
  independent of custom candidate-panel visibility
- when native Rime is active, arrow navigation moves inside the current page first, then maps right/down at the page edge to Rime `.pageDown` plus row 1 highlight and left/up at the page edge to Rime `.pageUp` plus previous-page last-row highlight
- if native highlight is unavailable, arrow navigation falls back to local panel selection and Space explicitly selects that Rime current-page index before generic native Space
- handles Rime's default paging punctuation (`-`/`=`, `,`/`.`) before symbol commit fallback, but falls back to punctuation when the native snapshot does not change so page-boundary punctuation is not swallowed
- offers composing ASCII symbols to Rime before punctuation fallback so schema keys such as apostrophe, semicolon, and slash stay available to the engine
- requests the character before a collapsed caret only for Chinese half-width
  quote keys; English and full-width quote output skips document context;
  the recorded prior insertion keeps ASCII-origin digits followed by `.`
  half-width without a period-key document read, while quote context maps
  whitespace/open punctuation to opening and text/digits/closing punctuation to
  closing
- records only the previous-character classification and context source in
  diagnostics, never surrounding or committed text
- highlight-only updates refresh marked text and the panel without restarting AI recommendation requests
- preserves an explicitly selected non-Rime row from the IMK/custom candidate window before falling back to native Rime Space
- native final Space, numeric, and mouse/panel candidate commits record local selection history before composition reset; partial native commits do not
- delegates commit-choice planning to `InputCommitDecisionRuntime`, including
  Space/Tab/Option-number priority, selected AI/segment/continuation/native row
  decisions, panel-number selection, accepted-AI candidate identity, and
  prefix-learning candidate selection
- delegates local lexical selection and commit side effects to
  `InputLexicalCommitRuntime`, including selection-history recording, bounded
  recent commit tracking, lexical profile refresh scheduling, and
  `candidateSelected` / `compositionCommitted` event construction
- delegates commit result planning and commit side-effect context construction
  to `InputCommitApplicationRuntime`; the coordinator still executes host
  insertion, marked-text cleanup, Rime reset, panel hide, anchor reset,
  AI/lexical runtime calls, and lifecycle event publication in order
- delegates input-turn side-effect sequencing to `InputTurnSequencingRuntime`;
  the coordinator executes ordered effects returned by the runtime instead of
  embedding commit, native conversion, lifecycle finish, and direct passthrough
  ordering inline
- validates planned turn effect order through `InputTurnSequenceValidator` before
  executing effects; violations and `KNOWTYPE_TURN_DEBUG=1` traces contain only
  turn metadata and effect names, never user text
- emits privacy-safe input latency stages through `InputDebugDiagnostics`,
  including `handle_key_total`, `commit_decision`,
  `turn_effect.<effectName>`, `refresh_composition`, and
  `publish_local_suggestion`; `KNOWTYPE_PERF_DEBUG=1` emits all traced stages,
  while `KNOWTYPE_INPUT_LATENCY_DEBUG=1` respects the configured latency budget
- explicit AI commits through Tab or Option+1 are excluded from prefix-learning history so provider continuations do not pollute local candidate selection signals
- delegates explicit AI accepted-learning records, typing-context events, and
  accepted-feedback span orchestration to `InputAIAcceptanceRuntime`; the
  coordinator still supplies commit context and performs host insertion
- explicit AI commits create a short-lived accepted-text span through
  `InputAIAcceptanceRuntime`; the span activates only after the post-insert
  caret is verified at the expected end of the inserted AI text
- external Backspace is not negative AI feedback on its own; it is recorded as
  feedback only when the current client and selected range prove the edit falls
  inside the active accepted AI span
- moved cursors, stale or unknown ranges, focus changes, new compositions, and
  expired spans cancel feedback tracking and learn nothing
- reserves Option+1 for the AI slot; when AI is not ready, Option+1 consumes the key without committing legacy continuation candidates
- native candidate mapping uses the encoded current-page index when present; ambiguous duplicate text without an index does not fall back to the retired local converter
- routes committed typing events and no-composition external Delete events
  through `InputAIAcceptanceRuntime`
- rejects stale candidate-panel publications by raw input, composition id,
  composition buffer, and cancellation state through
  `InputCandidatePanelPublicationRuntime`
- uses `InputTaskSupervisor` only for still-active background task categories;
  panel render work is supervised by `InputCandidatePanelPublicationRuntime`,
  and real-time AI request tasks are owned by
  `InputAIRecommendationRuntime`
- constructs AI recommendation input context and applies returned AI slot states
  to the candidate panel, while request lifecycle, active request ids,
  generation checks, task cancellation, and stale-result diagnostics live in
  `InputAIRecommendationRuntime`
- runs a lightweight AI schedule eligibility check before building lexical
  context or accepted-feedback snapshots; raw-too-short, cloud-disabled,
  partial-composition, and no-provider skip paths do not pay the lexical
  profile construction cost
- applies AI publications only to the AI slot after
  `InputAIRecommendationRuntime` validates request id, generation, composition
  id, raw revision, and raw input through `AIRecommendationPatch`
- delegates real-time AI schedule eligibility and skipped-state diagnostics to
  `InputAIRecommendationSchedulePolicy`; request construction, task lifecycle,
  stale-result checks, and patch validation are handled by
  `InputAIRecommendationRuntime`
- keeps post-commit AI acceptance side effects out of the key write path:
  accepted-learning writes, feedback tracking, and typing-context events are
  asynchronous or tracker-local side effects owned by
  `InputAIAcceptanceRuntime`
- schedules post-insert AI feedback caret verification through the dedicated
  host post-insert seam, not through delayed candidate-panel re-anchor
  scheduling
- schedules AI recommendation from raw input and confirmed locked prefixes only;
  while Rime is merely composing, current-page Rime candidates are not sent as
  AI context and the first candidate is not treated as locked text
- treats lazy AI runtime presence as an asynchronous recommendation capability,
  not as proof that a provider is configured; no-provider local continuation
  fallback remains available until an eager provider is known or a lazy provider
  has actually loaded, and stale resolved-composition fallback rows are cleared
  by `InputSuggestionStateRuntime` once lazy provider availability becomes
  known
- gates real-time cloud AI scheduling only on secret-like raw input or confirmed
  locked prefixes; normal technical tokens, commands, paths, URLs, and app
  context do not directly set `AI 已禁用`
- preserves the original confirmed locked-prefix text in AI requests, including
  intentional leading/trailing whitespace, while using trimmed text only for
  empty-prefix eligibility checks
- builds lexical profile and accepted-feedback snapshots for AI only when
  `InputAIRecommendationRuntime.shouldBuildRecommendationContext` says the
  provider state can use them; known-unavailable lazy providers keep the
  lightweight availability-probe path without repeated heavy context
  construction
- delegates real-time AI request timing to `InputAIRecommendationRuntime`: the
  coordinator can receive `.pending` only after provider dispatch, and stale
  transport results cannot overwrite newer raw input, composition id, or raw
  revision state
- merges persisted lexical profile terms into AI requests only when the stored profile schema matches the active Rime schema; in-memory recent commits and selection history can participate, but current-page Rime candidates do not
- requests lexical context and commit/selection refresh through
  `InputLexicalCommitRuntime`; underlying Rime userdb refresh reads existing
  snapshots only and does not call `sync_user_data`; profile JSON/Markdown
  staging, stale-write gates, and userdb parse diagnostics live outside the
  coordinator
- does not initialize or rebuild runtime lexicon engines in the IMK product path; Rime is the only production conversion source
- clears composition state for cancel and commit through
  `InputCompositionStateRuntime` and lifecycle plans from
  `InputCompositionLifecycleRuntime` while the coordinator keeps candidate-panel
  hide, Rime reset, marked-text cleanup, and runtime-event publication in order
- has post-refactor regression coverage for the cross-runtime paths that must
  remain order-stable after the extraction sequence: inline marked text,
  terminal placeholder composition, lifecycle close/deactivate/native-ended
  cleanup, delayed re-anchor stale gating, and AI typing-context snapshots
- receives candidate-panel publication results from
  `InputCandidatePanelPublicationRuntime` and asks
  `InputNativeCandidateNavigationRuntime` to map visible panel selection back
  into native/Rime candidate selection state
- emits privacy-safe `KNOWTYPE_STARTUP_DEBUG=1` timing logs for first
  composition begin and first candidate-panel materialization through
  `InputDebugDiagnostics`; logs include timing and state metadata, not user text
- emits privacy-safe IMK write diagnostics with
  `KNOWTYPE_CLIENT_WRITE_DEBUG=1`; logs include bundle id, write mode,
  handled/pass-through state, write kind, and reasons, never user text
- explicitly hides and invalidates the candidate panel on deactivate, close, reset, and native composition end because the panel uses `hidesOnDeactivate = false`
- keeps Rime/native candidate navigation authoritative through
  `InputNativeCandidateNavigationRuntime`; panel publication helpers live in
  `InputCandidatePanelPublicationRuntime`, while commit decisions and native
  conversion side effects remain in the coordinator
- relies on `InputCandidatePanelPublicationRuntime` to reject publication unless
  the current raw/native preedit composition is active, while preserving a
  raw/preedit fallback frame for transient empty Rime snapshots with non-empty
  raw input; stale suggestions, AI results, or delayed reanchors cannot revive a
  hidden panel
- resets the conversion engine when Delete clears the raw buffer, including native raw-bypass state from non-ASCII compositions
- flushes user selection history through `InputLexicalCommitRuntime` on
  deactivate and close; deactivate falls back
  to the current IMK client before committing active raw composition through the
  normal clear-owned-marked-text plus insert path
- clears KnowType-owned marked text when native handled/no-commit output ends
  with no active raw/preedit, because composition ended without inserted text
- asks `InputCandidatePanelPublicationRuntime` to schedule delayed candidate
  re-anchor through `InputControllerHost`; only the latest same-raw-input,
  same-composition reanchor is allowed to republish the panel
- delegates inline marked text, commit-only placeholder marked text, idle ASCII
  passthrough, and owned marked-text cleanup to
  `InputClientCompositionWriter`; the coordinator still decides when to refresh
  composition and when a successful marked-text write should schedule delayed
  re-anchor
- keeps suggestion freshness checks guarded by `SuggestionPublicationGuard`
  through `InputSuggestionStateRuntime`
- suppresses AI recommendation while the composition is only partially resolved, so half-pinyin marked text is not sent as a locked prefix

The coordinator remains IMK-free. Production host/client adapters live beside the IMK wrapper, while tests use fake clients, fake host scheduling, fake panel capture, and fake history persistence.
