# InputControllerCoordinator

`InputControllerCoordinator` owns the testable state machine behind `KnowTypeInputController`.

Current behavior:

- maps `InputKeyStroke` values through `InputKeyCommandMapper`
- owns the composing raw buffer, `CompositionBuffer`, composition id, input
  mode runtime, Rime snapshots, and native candidate navigation orchestration
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
- cancels any pending retired local-candidate task before synchronous native candidate publication, so an older background snapshot cannot overwrite a fresh native state update
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
- maps Option+/ to a session-local Chinese/ASCII text-mode toggle so
  terminal-style compatibility hosts can switch between Chinese placeholder
  composition and idle ASCII passthrough
- bypasses the input-mode preference reload throttle when the focused app bundle
  changes, so quick host switches do not reuse the previous host's text mode
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
- highlight-only updates refresh marked text and the panel without restarting AI recommendation requests
- preserves an explicitly selected non-Rime row from the IMK/custom candidate window before falling back to native Rime Space
- native final Space, numeric, and mouse/panel candidate commits record local selection history before composition reset; partial native commits do not
- delegates local lexical selection and commit side effects to
  `InputLexicalCommitRuntime`, including selection-history recording, bounded
  recent commit tracking, lexical profile refresh scheduling, and
  `candidateSelected` / `compositionCommitted` event construction
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
- rejects stale async candidate publications by raw input, composition id, composition buffer, cancellation state, and suggestion generation
- uses `InputTaskSupervisor` to replace stale local-candidate tasks; panel
  render work is supervised by `InputCandidatePanelPublicationRuntime`, and
  real-time AI request tasks are owned by `InputAIRecommendationRuntime`
- constructs AI recommendation input context and applies returned AI slot states
  to the candidate panel, while request lifecycle, active request ids,
  generation checks, task cancellation, and stale-result diagnostics live in
  `InputAIRecommendationRuntime`
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
- schedules AI recommendation from raw input and confirmed locked prefixes only;
  while Rime is merely composing, current-page Rime candidates are not sent as
  AI context and the first candidate is not treated as locked text
- treats lazy AI runtime presence as an asynchronous recommendation capability,
  not as proof that a provider is configured; no-provider local continuation
  fallback remains available until an eager provider is known or a lazy provider
  has actually loaded, and stale local fallback rows are cleared once lazy
  provider availability becomes known
- gates real-time cloud AI scheduling only on secret-like raw input or confirmed
  locked prefixes; normal technical tokens, commands, paths, URLs, and app
  context do not directly set `AI 已禁用`
- preserves the original confirmed locked-prefix text in AI requests, including
  intentional leading/trailing whitespace, while using trimmed text only for
  empty-prefix eligibility checks
- merges persisted lexical profile terms into AI requests only when the stored profile schema matches the active Rime schema; in-memory recent commits and selection history can participate, but current-page Rime candidates do not
- requests lexical context and commit/selection refresh through
  `InputLexicalCommitRuntime`; underlying Rime userdb refresh reads existing
  snapshots only and does not call `sync_user_data`; profile JSON/Markdown
  staging, stale-write gates, and userdb parse diagnostics live outside the
  coordinator
- does not initialize or rebuild runtime lexicon engines in the IMK product path; Rime is the only production conversion source
- clears composition state for cancel and commit while hiding the candidate panel through `InputControllerHost`
- receives candidate-panel publication results from
  `InputCandidatePanelPublicationRuntime` and asks
  `InputNativeCandidateNavigationRuntime` to map visible panel selection back
  into native/Rime candidate selection state
- emits privacy-safe `KNOWTYPE_STARTUP_DEBUG=1` timing logs for first
  composition begin and first candidate-panel materialization; logs include
  timing and state metadata, not user text
- emits privacy-safe IMK write diagnostics with
  `KNOWTYPE_CLIENT_WRITE_DEBUG=1`; logs include bundle id, write mode,
  handled/pass-through state, ranges, write kind, and reasons, never user text
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
- keeps provider-backed suggestion publication guarded by `SuggestionPublicationGuard`
- suppresses AI recommendation while the composition is only partially resolved, so half-pinyin marked text is not sent as a locked prefix

The coordinator remains IMK-free. Production host/client adapters live beside the IMK wrapper, while tests use fake clients, fake host scheduling, fake panel capture, and fake history persistence.
