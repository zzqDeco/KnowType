# Sources/KnowTypeInputMethod

`KnowTypeInputMethod` owns input-method interaction behavior.

Current package-level implementation covers:

- explicit IME session mode modeling for empty, composing, candidate, AI-pending, and protected ASCII/no-correction input
- candidate panel view model
- session commit policy for raw/prefix numeric shortcuts and native candidate selections
- legacy segmented composition buffering for package/session tests; production Chinese conversion is Rime-only
- candidate anchor range policy for IMK clients with known or unknown selection ranges
- candidate anchor resolver for IMK rects, line-height rects, Accessibility rects, scoped last-anchor fallback, safe screen fallback, and debug tracing
- custom AppKit candidate presentation styled as a compact macOS candidate list
- candidate panel row builder and renderer with raw input, commit-only preedit,
  locked prefix, AI status, and continuation rows
- candidate panel publication runtime for panel state, visibility decisions,
  async publication gating, delayed re-anchor, and panel diagnostics
- native candidate navigation runtime for Rime current-page selection,
  highlight, paging, boundary paging, and panel selection mapping
- composition state runtime for raw input, `CompositionBuffer`, composition id,
  raw revision, and delete-count state
- suggestion state runtime for current suggestion/raw-input snapshots, commit
  suggestion reads, and narrow no-provider fallback continuation cleanup
- candidate panel mouse hover, click commit, scroll paging, row accessibility, and PNG snapshot regression tests
- shortcut-to-commit behavior
- key intent modeling for key down, key up, modifier flag changes, cancel, delete, navigation keys, punctuation, and numeric candidate selection
- process-wide `InputModeStateMachine` state for text mode, punctuation
  language, punctuation source, symbol width, and generation; `Option + /`
  relinks punctuation while changing Chinese/ASCII mode, `Option + .` is a
  Chinese-only manual override, and `Shift + Space` changes width independently
- host compatibility write modes for inline composition, commit-only
  composition, ASCII passthrough, and missing-client disabled handling
- host composition write state through `InputClientCompositionWriter`, which
  owns owned-marked-text cleanup and placeholder/inline marked-text carrier
  writes while keeping raw user text out of write state
- runtime loading of user-owned JSON/TSV lexicon directories into the local Chinese engine
- runtime lexicon snapshot refresh at new-composition boundaries so local dictionary file changes can be picked up without reinterpreting active marked text
- persisted prefix selection history used as a local-only ranking signal
- input-method selection history runtime for protected-input filtering, recent
  selection cache, runtime event construction, and persistence flush delegation
- lexical commit runtime for bounded recent commit tracking, selection-history
  orchestration, lexical profile refresh scheduling, and commit/selection event
  payloads
- composition lifecycle runtime for begin/finish plans, first-begin trace-once
  state, finish reason mapping, and owned marked-text clear intent
- commit application runtime for mapping commit results to coordinator plans,
  and constructing AI/lexical side-effect contexts without performing host
  writes
- input turn sequencing runtime for value-only ordering of commit, native
  conversion, lifecycle finish, and direct passthrough side effects
- input turn sequence validation and privacy-safe turn debug logging for
  replaying side-effect order without recording user text
- AI recommendation schedule policy for pure schedule/skip decisions before
  asynchronous provider requests are started
- AI recommendation runtime for IMK-side request construction, cancellation,
  stale-result checks, diagnostics, and AI slot state callbacks
- AI acceptance runtime for post-commit accepted-learning records, typing
  context events, accepted-feedback tracking orchestration, and protected or
  secret gates
- optional `RimeConversionEngine` boundary with a dynamic `librime` bridge and deterministic `TraditionalInputEngine` fallback
- lexical profile snapshots for AI recommendation that exclude Level 0/protected app commits and protected-app selection history
- `InputTaskSupervisor` cancellation for runtime lexicon reload and panel
  rendering work
- testable host/client seams for the IMK controller boundary
- synchronous Rime suggestion publication state
- Level 0 no-provider routing for protected input
- minimal InputMethodKit server bootstrap guarded by `canImport(InputMethodKit)`
- `KnowTypeInputMethodApp` bundle entry assembled by `scripts/build-inputmethod-bundle.sh`

The AppKit candidate panel is the active candidate presentation for the IMK bundle. This avoids the `IMKCandidates` failure mode where the system panel accepts data but does not become visible in some host apps. `CandidatePanelRowBuilder` owns row ordering and selection identity for both state and rendering. `InputCandidatePanelPublicationRuntime` owns candidate-panel state publication, explicit hide reasons, async stale-snapshot gating, delayed re-anchor generation, and panel diagnostics. Commit-only preedit rows render above candidates when the host text field receives only a placeholder carrier. Prefix rows are rendered first after any preedit row, continuation rows after them, and raw input is rendered only while no suggestion exists. The panel uses native AppKit material, system colors, compact row metrics, row hit-testing, and accessibility elements. `Space` commits the visible snapshot for the current raw input; mouse click commits the same `CandidatePanelSelection` as keyboard selection and never commits disabled status rows.

When a provider is configured, the IMK controller publishes raw marked text and current-page Rime prefix candidates synchronously; provider-backed AI recommendation rows remain asynchronous. The first candidate publication does not include local fallback continuation rows. If the provider fails or returns no usable continuation, the async update keeps the AI slot unavailable instead of substituting local fallback text, so `Space` still commits through Rime while `Tab` does not present fake AI output. Ready AI remains the second shortcutable slot; pending, unavailable, and ineligible AI states are disabled status rows with muted styling, no shortcut, no hover selection, and no click commit. Without a provider, the product input path still uses Rime only for Chinese conversion.

`InputAIRecommendationSchedulePolicy` decides whether the current input state is
eligible to start that asynchronous AI recommendation. It returns the skipped AI
state and diagnostic reason for unstable composition, short triggers,
secret-like text, disabled cloud continuation, and missing provider cases.
`InputAIRecommendationRuntime` owns request construction, task cancellation,
patch validation, lifecycle diagnostics, and AI slot state callbacks; the
coordinator applies the returned state to the candidate panel.
`InputAIAcceptanceRuntime` owns post-commit AI side effects after the
coordinator has chosen a commit result: accepted-learning writes,
typing-context events, accepted-feedback tracking, and protected/secret gates.
`InputLexicalCommitRuntime` owns local lexical commit and selection side
effects after the coordinator has chosen a commit or selection fact: bounded
recent commits, protected selection-history recording, lexical profile refresh
scheduling, and commit/selection event payload construction. The coordinator
still owns host insertion, composition lifecycle, and asynchronous event-bus
publication.
`InputCompositionStateRuntime` owns pure raw composition state and returns
snapshots for coordinator side effects. The coordinator still decides the order
of Rime calls and marked-text refresh, while input turn sequencing makes commit,
native, lifecycle, and passthrough effect order explicit.
`InputSuggestionStateRuntime` owns the current `SuggestionResponse` and
associated raw input. It keeps suggestion commit snapshots and stale checks out
of the coordinator while preserving the Rime-only product path: it does not
create pending fallback continuations or restart the retired async local
candidate pipeline.
`InputCompositionLifecycleRuntime` owns composition begin/finish plans.
`InputCommitApplicationRuntime` owns commit-result plan and context
construction. `InputTurnSequencingRuntime` owns the value-only order of the
effects that follow those decisions. The coordinator still executes the actual
side effects: accepted-feedback preparation, AI/lexical recording,
KnowType-owned marked-text cleanup, host insertion, Rime reset,
candidate-panel hide, anchor reset, and lifecycle event publication.
`InputTurnSequenceValidator` checks these sequences for known ordering
regressions and feeds privacy-safe `KNOWTYPE_TURN_DEBUG=1` diagnostics; it does
not execute effects or inspect committed text.

The IMK controller marks composing text with `IMKTextInput.setMarkedText`. Inline-compatible hosts, including browsers, text editors, IDEs, Electron shells, and JetBrains-style clients by default, receive Rime preedit as attributed marked text. Terminal-style or explicit override commit-only hosts receive a full-width-space attributed placeholder so IMK composition ownership and candidate anchoring stay stable without exposing raw pinyin in the host field. `InputClientCompositionWriter` owns that carrier choice, idle ASCII passthrough decisions, and KnowType-owned marked-text cleanup, while `InputClientWriteCoordinator` owns the low-level `setMarkedText`/`insertText` calls and privacy-safe diagnostics. Their real preedit is shown in the candidate panel instead. Candidate anchor lookup is delegated to `CandidateAnchorResolver`, which tries at most four fresh IMK `firstRect` ranges, then an unexpired same-composition/app/screen anchor, at most four strategic line-height positions, one composition/app-throttled Accessibility resolve, and finally a stable safe point inside the screen visible frame. The panel no longer follows the mouse pointer when host text geometry is temporarily unavailable.

Product commit decisions are shared through the session commit policy and
coordinator: `Space` commits the highlighted/current Rime candidate, selects a
non-highlighted native row by stable current-page Rime index before falling
through to generic native Rime space handling, or commits raw input when Rime is
degraded; `Return` commits raw composition, `Tab` commits ready AI, and numeric
shortcuts call Rime current-page selection. Punctuation commits the current
Rime candidate/composition plus mapped punctuation; an idle period after an
ASCII digit stays `.`. `Option+/` changes the process-wide linked text mode.
`InputNativeCandidateNavigationRuntime`
owns Rime navigation decisions; the coordinator still applies commit results,
learning, marked text, insertion, and panel publication. Idle printable input
is returned unhandled whenever the shared mode is ASCII and width is half;
full-width printable ASCII is transformed and inserted by KnowType. All hosts start in
linked Chinese mode; terminal-style hosts differ only by using placeholder
carrier during composition. Duplicate native surface forms keep their Rime
stable index, and runtime lexicon reload no longer replaces the production
conversion session.

Candidate paging keeps 6 visible rows per page in adaptive horizontal mode so short candidates do not force a vertical panel. Vertical-list mode can show up to 9 visible rows per page. Arrow keys move one selectable row, PageDown/PageUp preserve the selected row's visible offset on the target page, and short final pages clamp to their last available row. Scroll-wheel paging maps to PageDown/PageUp with a small delta threshold to avoid trackpad jitter. Screenshot baselines under `Tests/KnowTypeInputMethodTests/__Snapshots__/` cover light horizontal, dark vertical, and AI status panel states.

`InputLexicalCommitRuntime` records local lexical commits and delegates
recently committed prefix candidate learning to `InputSelectionHistoryRuntime`.
That selection runtime skips protected selected text and raw input, persists
accepted selections through `UserSelectionHistoryPersistence`, and feeds only
the in-process recent selection cache into lexical profile refresh.
Persistence appends newly selected prefixes on a shared serial queue and
controller shutdown waits for pending writes, so stale snapshots do not
overwrite newer selections from another host app. The ranking signal stays
local; AI requests receive only summarized lexical context, not the full
selection log.

MVP manual acceptance still must verify candidate window behavior in host apps because IMK text input behavior varies across AppKit, browser, Electron, and terminal contexts.
