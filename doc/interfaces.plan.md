# KnowType Interfaces

This document records current cross-layer contracts. Provider-specific shapes, UI render details, and host-app quirks should not leak across these boundaries.

## Provider Request

Internal request shape:

```text
LLMRequest {
  task: correction | continuation | contextDigest | polish
  lockedPrefix?: string
  rawInput?: string
  candidateHints: [              // legacy-compatible; realtime continuation sends []
    { text: string, nativeIndex?: number, pageNumber: number, isHighlighted: boolean, comment?: string }
  ]
  locale: zh-CN | en-US | mixed
  appContext?: string
  maxCandidates: number
  lengthLevel?: short | medium | long
  outputSchema: json
  contextDocuments: { [name: string]: string }
}
```

Swift uses camelCase property names. Adapters may serialize to provider-specific payloads, but they must preserve the same semantic fields.

## Provider Response

All providers normalize to:

```text
LLMResponse {
  candidates: [
    { text: string, confidence?: number, reason?: string }
  ]
  diagnostics: [string]
}
```

Provider adapters must not expose native OpenAI, Anthropic, Gemini, Ollama, or custom HTTP response shapes outside `KnowTypeProviders`.

Provider adapters use a shared structured-output contract where the endpoint supports it. Candidate tasks
(`correction`, `continuation`, and `polish`) use a `candidates` array with `text`, `confidence`, and `reason`.
`contextDigest` uses a separate `{ markdown: string }` response and is normalized into an `LLMResponse` candidate
only after strict decoding. OpenAI Chat and Responses prefer `json_schema` with `strict=true`; OpenAI-compatible
endpoints that reject schema fields fall back once to JSON mode and report `structured_schema_unsupported` in
`LLMResponse.diagnostics`. Gemini and Anthropic send native schema hints and also fall back when the endpoint
rejects those fields. Ollama and custom HTTP do not claim provider-enforced schema, but their outputs still pass
through strict local decoding instead of line-based candidate extraction.

Real-time AI recommendation requests use `task: continuation`, `rawInput`, app context, and `contextDocuments["ENV.md"]` / `contextDocuments["CORRECTION.md"]`. `lockedPrefix` is present only for text the user has already confirmed or resolved; unselected Rime candidates are not sent to the provider and must not be promoted into a locked prefix. Background memory updates use `task: contextDigest` with the pending event batch in `rawInput` and the current `ENV.md` as a context document.

Provider prompts are task-specific. Continuation requests distinguish confirmed prefixes from unconfirmed raw input:

- when `lockedPrefix` is present, candidate `text` must be directly appendable after it and must not repeat, paraphrase, translate, rewrite, or polish the locked prefix
- when `lockedPrefix` is absent, candidate `text` is a full commit-ready recommendation inferred from `rawInput` and context documents

When a non-empty `lockedPrefix` exists, cloud eligibility is gated by that locked prefix alone; otherwise it is gated by raw input length. Runtime output must preserve the original locked-prefix text, including intentional leading or trailing whitespace, and may only use trimmed text for emptiness and sanitizer comparisons. `AI 已禁用` is reserved for secret-like raw input or confirmed locked prefixes. Correction, polish, and context digest requests keep separate prompts so continuation examples cannot leak into those tasks. The local prefix-lock sanitizer remains authoritative whenever a locked prefix exists, even when a provider follows the prompt.

## Input Client Compatibility

Host write behavior is selected before each key write:

```text
InputClientWriteMode =
  inlineComposition
  commitOnlyComposition
  asciiPassthrough
  disabled
```

Unknown and standard text clients use `inlineComposition`. Terminal and iTerm
default to `asciiPassthrough` while idle. Xcode, VS Code, Codex, common Electron
hosts, and JetBrains IDEs default to `commitOnlyComposition`, so the candidate
panel can appear without exposing raw inline preedit. Commit-only composition
uses a full-width-space `NSAttributedString` marked-text placeholder with marked
attributes to keep the IMK composition and candidate anchor alive, then commits
with `insertText`. `Option + /` toggles the
session text mode in compatibility hosts; ASCII mode passes idle printable input
back to the focused app. Missing clients use `disabled`; printable idle input is
returned as unhandled so the host can keep normal typing behavior. All write
modes keep replacement ranges as
`{NSNotFound, NSNotFound}` unless a future reconversion feature introduces an
explicit owned range.

## Provider Kinds

- `openai_chat`
- `openai_responses`
- `anthropic_messages`
- `gemini_native`
- `ollama_native`
- `custom_http`

Runtime creation goes through:

```text
ProviderFactory.makeProvider(configuration:httpClient:) -> LLMProvider
```

## Provider Profiles

Provider metadata is stored separately from API keys:

```text
ProviderProfile {
  id
  displayName
  kind
  baseURL
  model
  timeoutSeconds
  headers
  secretName?
  customBodyTemplate?
  customResponsePath?
  isDefault
}
```

Default file-backed profile storage writes `providers.json` under the user's Application Support `KnowType` directory only on explicit save. Runtime cold-start paths use the no-create loader, so a missing provider profile does not create `Application Support/KnowType` merely because the IMK host was launched.

`secretName` resolves through `SecretStore`. On macOS, `KeychainSecretStore` stores API keys under the `KnowType` service. Tests and non-UI code can use in-memory or read-only dictionary stores.

When `providers.json` is missing or empty, settings and runtime loading share seeded defaults. The default profile is local OpenAI-compatible at `http://127.0.0.1:8317/v1`, may leave `model` blank for discovery, and does not embed an API key.

Settings validation rules:

- display name cannot be empty
- base URL must be HTTP(S) with a host
- timeout must be positive
- remote OpenAI-compatible profiles require an explicit model ID
- local OpenAI-compatible profiles may leave model blank for `/v1/models` discovery
- cloud profiles require a new key or an existing non-empty secret
- custom HTTP profiles require body template and response path, but may omit the API key
- profile saves publish new settings only after profile metadata and required secret mutations succeed

Settings connection tests:

- build a transient `ProviderConfiguration` from the current draft
- use a non-blank draft API key for the test request only
- reuse an existing saved `secretName` value only when the draft key is blank and the saved secret still belongs to the same provider kind and endpoint credential scope
- fail before sending a request when a required key is missing
- publish current field validation errors before failing an invalid test request while preserving save-only validation errors
- do not write provider JSON or mutate `SecretStore`
- clear stale status when draft fields change
- ignore in-flight results for superseded draft/profile snapshots
- keep transient diagnostic failures out of the persistent save/load error slot
- preserve existing save/load errors after diagnostic success
- avoid reusing a saved remote secret when a blank-key draft switches to a local endpoint, another remote endpoint, or another provider protocol

## Local Install State

Local install scripts record recoverable install metadata under the user's
Application Support directory. `install-state.json` is schema version `1` and
contains the install time, source (`local-build`, `dmg-dev-preview`,
`release-zip`, or `bundle`), bundle version/build, optional git commit/tag,
installed app and prefPane paths, release manifest digest, and the previous
backup id. It describes install artifacts only; it does not snapshot Rime
userdb, provider profiles, Keychain secrets, or AI context files.
Default install and rollback paths do not launch `KnowTypeInputMethodApp`, do
not select the input method, and do not initialize Rime user data; first real
typing after the user selects KnowType is normal product use rather than an
install side effect.
If macOS prelaunches the IMK host while refreshing TIS or LaunchServices state,
controller cold start remains read-only: Rime native sessions, provider profile
loading, user selection history, AI learning/feedback files, lexical profiles,
`ENV.md`, and `CORRECTION.md` are lazy and are not created until a real input,
AI request, or explicit maintenance action needs them.
Lazy provider wrappers expose provider availability only after their loader has
resolved a real provider state, so local no-provider fallback rows are not
suppressed merely because the wrapper exists. Accepted learning and feedback
startup reads always join their in-process locks and join existing file locks
when present, but do not create lock files for missing histories.
If the host process is already running, install/rollback must fail before
replacement instead of killing it, since forced shutdown can flush Rime userdb
files and would count as a user-data mutation.

Install backups live under `Backups/<backup-id>/`. Each backup manifest records
schema version, backup id, creation time, app version/build, bundle identifier,
app checksum, whether a prefPane was included, and the restore command. Rollback
restores only `KnowType.app` and optional `KnowType.prefPane`, then refreshes
LaunchServices and input-source preferences.

`scripts/diagnose-inputmethod.sh --json` is the stable machine-readable
diagnostic surface for local tooling. It emits top-level `install`, `bundle`,
`preferencePane`, `rime`, `ai`, `userData`, `backups`, `warnings`, and
`failures` objects. The JSON output must not contain API keys, user text,
candidate text, or complete lexicon/userdb contents.
Install postflight parses that JSON and treats any non-empty `failures` array as
a warning even when the diagnostic process exits successfully.

## Candidate Data

Core candidate types:

- `TextRange`: a Swift `Character`-offset range over the current raw input buffer.
- `CandidateSegment`: one resolved segment with raw range, token range, reading, output text, and passthrough status.
- `CorrectionCandidate`: corrected prefix candidate with level and protected ranges.
- `TraditionalInputCandidate`: local pinyin-engine prefix candidate.
- `TraditionalInputLexiconEntry`: authorized local lexicon row with normalized pinyin tokens and one or more outputs.
- `TraditionalInputLexiconOutput`: local lexicon output text and confidence score.
- `TraditionalInputLexiconCatalog`: combined authorized local lexicon entries plus load diagnostics.
- `TraditionalInputLexiconDirectoryResolver`: shared local lexicon directory discovery for runtime and settings.
- `TraditionalInputLexiconFileSource`: file and directory loader for local lexicon resources.
- `TraditionalInputLexiconResourceLoader`: JSON/TSV parser for audited local lexicon resources.
- `TraditionalInputSeedLexicon`: packaged clean-room seed lexicon loaded through the same file/resource path.
- `ManagedLexiconPack`: pinned, license-aware dictionary source descriptor.
- `InstalledLexiconPackMetadata`: local metadata written beside installed managed lexicon TSV files.
- `ManagedLexiconPackInstaller`: downloader, verifier, converter, and atomic writer for managed lexicon packs.
- `InputMethodLexiconRuntime`: input-method runtime loader for user-owned local lexicon directories.
- `LockedPrefix`: selected immutable prefix.
- `ContinuationCandidate`: text after the locked prefix only.
- `AIRecommendationCandidate`: ready AI slot payload with the locked prefix, optional continuation, display text, provider, confidence, and context version.
- `AIRecommendationState`: input-method AI slot state: idle, pending, ready, ineligible, or unavailable.
- `AITypingEvent`: committed typing event used by the background memory runtime.
- `AIAcceptedLearningRecord`: local-only JSONL record for an AI recommendation the user explicitly accepted.
- `AIAcceptedLanguageSummary`: bounded accepted-AI term, style, and recent-commit summary used by lexical profile merging.
- `RimeUserDBTextSnapshot`: text export snapshot from Rime user data sync.
- `RimeMaintenanceService`: background owner of explicit `sync_user_data`, userdb snapshot discovery, and idle/manual maintenance policy.
- `LexicalProfileRuntime`: input-method runtime that merges persisted profile terms with recent commits and selection history, schedules background profile refresh from existing userdb snapshots, and clears summary-ready observer state when refreshes are cancelled during controller close.
- `LexicalContextSnapshot`: top-K lexical/tone summary rendered as `LEXICAL_PROFILE.md` and hashed into AI cache keys.
- `SuggestionResponse`: UI-facing snapshot containing `prefixCandidates`, `lockedPrefix`, `continuationCandidates`, and `latencyMs`.
- `ConversionEngineSnapshot`: Rime-facing snapshot containing raw input, preedit, current-page candidates, highlighted index, page size, page number, page-end state, and engine name.
- `CandidatePanelFrame`: candidate-panel presentation intent with composition id, raw revision, raw length, anchor source, panel model, and explicit visibility reason.
- `AIRecommendationPatch`: AI slot-only update guarded by request id, generation, composition id, raw revision, and raw input.

Raw input is tracked outside `SuggestionResponse` by the input-method session, for example through stale-result guards such as `latestSuggestionRawInput`. Protection metadata lives on correction candidates, locked prefixes, and protected ranges rather than on the top-level suggestion response.

Core correction and traditional-input candidates may carry `rawRange` and `segments` for offline/session tests. The production IMK coordinator no longer generates segment candidates from `TraditionalInputEngine`; Rime candidates are treated as whole-prefix candidates over the current raw input.

`InputContext.userSelectionHistory` is a local-only ranking hint. It may reorder prefix candidates that were already generated by the local correction engine, but it must not create new candidates and must not be serialized into provider requests. The IMK frontend may persist this history locally in `user-selection-history.json`; provider adapters still receive only `LLMRequest`.

`TraditionalInputEngine()` loads `TraditionalInputSeedLexicon` first. `TraditionalInputEngine(additionalLexiconEntries:)` is the public extension point for larger local lexicons. The engine trims and lowercases injected pinyin tokens, ignores empty rows, merges duplicate pinyin keys through its private index, and uses those entries for both spaced and compact pinyin parsing.

`TraditionalInputLexiconResourceLoader` accepts JSON resources shaped as `[TraditionalInputLexiconEntry]` or TSV rows in `pinyin<TAB>text<TAB>confidence` form. TSV confidence is optional and defaults to `0.72`. The loader returns typed errors for invalid UTF-8, malformed rows, empty text, or out-of-range confidence.

`TraditionalInputLexiconCatalogLoader` accepts named resources, loads each one independently, preserves valid entries, and returns diagnostics for failed resources. `TraditionalInputLexiconCatalog.makeEngine()` is the preferred handoff into `TraditionalInputEngine`.

`TraditionalInputLexiconFileSource` infers `.json` and `.tsv` formats from file extensions, reads explicit file lists or sorted directory contents, skips hidden directory entries and known managed-pack metadata filenames, and reports unsupported or unreadable files through catalog diagnostics.

`TraditionalInputLexiconDirectoryResolver` resolves `KNOWTYPE_LEXICON_DIR`, colon-separated `KNOWTYPE_LEXICON_DIRS`, and `~/Library/Application Support/KnowType/Lexicons`, trimming empty paths and de-duplicating standardized file paths while preserving order.

`InputMethodLexiconRuntime` uses the shared resolver, then creates the `TraditionalInputEngine` used by legacy package/demo paths. It is not consulted by the production IMK key path after the Rime-only transition.

`InputMethodLexiconRuntime.snapshot()` reports each configured directory's existence and supported JSON/TSV resource files with modification metadata. This remains available for legacy package/demo paths and settings diagnostics. The production IMK frontend does not refresh or rebuild `TraditionalInputEngine` after the Rime-only transition.

Rime userdb maintenance is separate from the conversion session. The default lexical-profile refresh path reads an
existing `*.userdb.txt` snapshot only; it does not call `sync_user_data` on commit, Space, number selection, paging,
or candidate-panel refresh. Explicit sync is exposed through `RimeMaintenanceService.syncUserDataIfIdle` or future
manual diagnostics/settings actions, so userdb locking and disk IO cannot run on the IMK hot path.

Interactive correction calls use `TraditionalInputQueryOptions.interactive`. The budget caps tokenization paths, recursive parse states, candidate output count, segment candidate output count, and partial-match fanout. Offline or test callers may omit the options for broader exhaustive parsing.

`ManagedLexiconPackInstaller` currently supports the recommended `rime-pinyin-simp` pack. It downloads the pinned Rime source dictionary, verifies the expected SHA256, converts Rime rows shaped as `text<TAB>pinyin<TAB>weight?` into KnowType TSV, writes the TSV atomically, and writes metadata containing source, version, checksum, license, entry count, and install date. It refuses to overwrite an existing output file unless `force` is true.

`LexiconSettingsViewModel` uses the shared resolver for settings status. It uses `TraditionalInputLexiconFileSource` for entry counts and diagnostics, can create missing directories or a non-overwriting `knowtype-sample.tsv`, and can install the recommended managed lexicon pack on explicit user action. It displays `*.metadata.json` pack metadata but does not treat metadata files as lexicon resources.

Input-method presentation maps `SuggestionResponse` into compact candidate rows:

- raw input is shown only when no prefix or continuation suggestion exists
- Rime prefix candidate 1 is the first selectable row
- the AI recommendation slot is fixed as the second visible row when it has a visible state
- remaining Rime prefix candidates follow the AI slot
- full candidates cover the entire raw buffer and commit as complete Chinese text
- segment candidates are retired from the production IMK path
- legacy continuation candidates remain in core/session tests; provider-backed IMK continuation uses the AI slot instead
- rows are paged through `CandidatePanelPagingState`; adaptive layout uses up to 6 visible rows per page, while vertical-list mode may use up to 9
- production IMK key handling first shows raw marked text, then publishes current-page Rime candidates synchronously while the AI slot resolves separately
- no-provider fallback continuation rows are not added synchronously to the IMK panel

Ready AI recommendations are selectable through Tab, explicit Option-number, and mouse click, but they do not take
ordinary numeric shortcuts from Rime candidates. Pending, unavailable, and ineligible AI states are rendered as
disabled status rows: they preserve the visible slot but have no selection identity, no numeric shortcut, and no
commit behavior. Mouse hover, click commit, keyboard selection, and accessibility selected children all consume the
same `CandidatePanelSelection` values so click commits match keyboard commits.

## Rime Hot Path

`KnowTypeConversionEngine` is the IMK boundary for base conversion. `RimeConversionEngine` is the production implementation:

- `process(.text)`, `.space`, `.commitComposition`, `.selectCandidateOnCurrentPage`, `.highlightCandidateOnCurrentPage`, `.pageUp`, and `.pageDown` call the native Rime session synchronously.
- Native Rime session creation is lazy. Non-ASCII raw-bypass mode is checked
  before session creation, so continuing a bypassed composition with ASCII or
  navigation keys does not initialize Rime user/log directories until reset and
  a later native conversion actually starts.
- `ConversionEngineSnapshot.suggestionResponse` maps only the current Rime page into prefix candidates; full candidate-list iteration is not part of the key path.
- Numeric shortcuts select the displayed current-page candidate with `select_candidate_on_current_page`.
- Marked text mirrors `ConversionEngineSnapshot.preedit` while Rime has composition. If Rime commits part of a long input and keeps composition active, KnowType inserts the commit text and keeps showing the remaining Rime preedit instead of reverting to raw pinyin.
- Ordinary digits `1...9` select Rime current-page candidates whenever native composition is active, even if the custom panel is hidden or the native snapshot currently has candidates without raw/preedit text. Out-of-range digits are consumed by the active composition and do not commit AI or append a literal digit.
- With no active text/native composition, ordinary Space and `0...9` are direct passthrough text insertions at the current cursor. They ignore lingering host `markedRange` values and use `NSNotFound`; stale candidate-panel or AI state must not capture those keys.

## IMK Client Writes

KnowType treats host-reported `markedRange` as advisory. It may be used by
candidate anchoring and diagnostics, but ordinary text writes must not use it as
a replacement range because some host apps can report stale ranges after fast
Space/Return or focus changes.

Current write contract:

- composing `setMarkedText`, clear-marked `setMarkedText("")`, ordinary
  `insertText` commits, and idle Space/digit passthrough all use
  `NSRange(location: NSNotFound, length: NSNotFound)`
- commit-only hosts receive a full-width-space attributed placeholder marked
  text while composition is active; raw pinyin and candidate text are not
  written inline
- clear-marked writes are only issued for KnowType-owned marked text; idle
  Return/Enter must not clear stale host marked ranges before returning the key
  to the app
- KnowType has no reconversion or selected-range replacement path today
- future reconversion must maintain an explicit KnowType-owned replacement
  range, reset it after commit, and must not directly trust `client.markedRange`
- `KNOWTYPE_CLIENT_WRITE_DEBUG=1` logs write kind, composition id, raw length,
  selected range, reported marked range, chosen replacement range, and reason
  without logging user text
- Arrow navigation updates Rime's current-page highlight. Right/down at the current page end moves to the next page and highlights row 1; left/up at the current page start moves to the previous page and highlights its last row.
- Rime-compatible paging punctuation (`-`/`=`, `,`/`.`) first attempts `.pageUp`/`.pageDown`; when the native snapshot does not change, the key falls back to the normal punctuation commit path so page shortcuts do not swallow punctuation at page boundaries.
- Other composing ASCII symbols are offered to Rime before KnowType punctuation fallback so schema keys such as apostrophe, semicolon, and slash can be handled by the engine.
- Explicit `PageUp`/`PageDown` are forwarded to the native engine whenever composition is active, even if the custom panel is hidden because anchoring failed.
- Rime initialization failure produces `engineName: rime-unavailable` and no candidates. The coordinator keeps raw input and raw commit usable instead of falling back to the retired local converter.
- xctest processes use temporary Rime user/log directories so tests do not lock or mutate the user's live Rime DB.
- The hot path emits `InputFrame`/`CandidatePanelFrame`-style state and side-effect events. It must not call AI providers,
  lexical profile write APIs, userdb sync, or candidate-panel AppKit APIs directly.

Candidate panel sizing is measurement-first. `CandidatePanelRenderer` owns row semantics only; the
`CandidatePanelLayoutEngine` measures visible rows, chooses horizontal layout for 4-6 complete candidates when
possible, switches to vertical layout for long phrases, and returns the final panel size, origin, row frames, and
per-row text limits used by the AppKit view. The layout plan must keep shortcut/selectable rows in sync with
rendered rows; constrained vertical layouts compress row height and spacing instead of dropping rows after
shortcuts are assigned. Shortcut labels are measured instead of using a fixed reserved slot. Horizontal rows use
their own shortcut label width; vertical rows align only the rows that have shortcuts to the current page's widest
shortcut label; rows without shortcuts reserve no shortcut space.

The native AppKit candidate panel is a borderless non-activating `NSPanel` at `.popUpMenu` window level, with
all-spaces/full-screen auxiliary behavior, `isFloatingPanel`, `worksWhenModal`, and `hidesOnDeactivate = false`.
Panel placement is search-aware: ordinary text fields prefer the visual-below-caret placement, while Spotlight
uses a visual-above-caret preference so search result overlays do not cover candidates. This avoids private APIs,
screen-saver level, or shielding levels. The visual style uses compact rows, `hudWindow` material, dynamic system
colors, and continuous corners so it stays close to macOS native candidate panels.

Because the panel does not hide automatically on app deactivation, the input-method coordinator explicitly hides it
on commit, cancel, deactivate, close, reset, and native composition end. Candidate-panel publication is frame-based:
updates carry `CandidatePanelVisibilityReason`, composition id, raw revision, raw length, and anchor source through
`CandidatePanelPresenter`. Stale suggestions, delayed reanchors, and AI patches must not make the panel visible
after composition teardown. A transient empty Rime snapshot does not hide the panel while KnowType still has non-empty
raw input; the presenter keeps a raw/preedit fallback frame until Rime context recovers or composition ends. With
`KNOWTYPE_PANEL_DEBUG=1`, panel logs include frame or cleanup reasons such as `composition_active`,
`composition_ended`, `deactivate`, `close`, `reset`, `native_ended`, `layout_impossible`, and `stale_update`,
plus placement preference and the final visual-above/visual-below choice.
Key event and text callbacks pass only the `IMKTextInput` client supplied by the IMK callback, so idle printable input
with a missing sender can pass through instead of reusing a stale current client. Commit, candidate, deactivation, and
close-style lifecycle callbacks may use the current IMK client as a final flush fallback when the callback sender is not
an `IMKTextInput`, so pending raw text is not dropped during lifecycle teardown. Teardown only clears marked text that
KnowType owns; native handled/no-commit end states clear that owned marked text because composition has ended without
inserted text.

The AppKit candidate panel exposes row accessibility elements. Enabled candidates use button semantics with labels
that include the visible shortcut and candidate text; ready AI labels include `AI 推荐`; disabled AI status rows use
static-text semantics. Selection changes post focused-element and selected-children notifications. Screenshot
regression tests render fixed examples to PNG baselines under `Tests/KnowTypeInputMethodTests/__Snapshots__/`.

`CompositionBuffer` keeps `rawInput`, resolved segments, active range, display text, and commit text separate for legacy/session tests. The production IMK path no longer generates local segment candidates; Rime owns composition and candidate commit for Chinese input.

## Candidate Geometry

Candidate panel movement consumes `CandidateAnchorResult`. UI code should not use pointer location as a moving fallback.

Resolver source priority:

1. marked and selected `firstRect` ranges
2. insertion-point `firstRect`
3. line-height rectangles
4. Accessibility focused-range bounds when available
5. same-composition scoped last usable anchor
6. safe screen fallback inside the visible frame

The resolver accepts zero-width caret rects with valid height and rejects zero-height, non-finite, offscreen, or stale cross-composition anchors.

## Shortcut Contract

- `Space` commits the highlighted/current Rime candidate for the current raw input.
- with no active composition, `Space` inserts a normal space instead of being consumed by the input method.
- when Rime is unavailable, `Space` commits raw input instead of blocking to compute hidden local candidates.
- `1...9` select Rime current-page candidates during native composition, independent of candidate-panel visibility.
- with no active composition, `0...9` are inserted as ordinary digits and do not open the candidate panel.
- `Return` / `Enter` commits the original raw composition.
- `Tab` commits the AI recommendation only when the AI slot is ready; pending, unavailable, disabled, or ineligible AI keeps the composition.
- `Tab` does not trigger AI continuation while the composition is in a legacy partial-segment state.
- `0` commits raw composition when correction candidates are visible.
- visible numeric shortcuts commit rows on the current Rime candidate page only; after the AI slot, native alternatives keep their visible row numbers.
- unmatched digit keys in native composition are consumed instead of appending raw digits; outside native composition, unmatched digits continue composing as literal digits.
- plain punctuation is offered to Rime first while composing; if Rime declines, KnowType commits the current composition display plus punctuation, or inserts punctuation directly with no composition.
- `Option + .` toggles Chinese/English punctuation for the active controller session.
- `Option + /` toggles Chinese/ASCII text mode for the active controller session; compatibility hosts use it to switch between Chinese commit-only composition and idle ASCII passthrough.
- `Option + 1` commits the ready AI recommendation explicitly; when AI is pending, unavailable, disabled, ineligible, or idle, it is consumed without committing legacy continuations.
- `Option + 2...9` commits legacy continuation rows when they are present.
- `Option + R` requests polish and may rewrite the prefix.

Input attributes are represented by `InputModeState`: text mode, punctuation language, and symbol width are separate fields, so half-width punctuation does not imply ASCII text mode. `InputModePreferences` persists normal-app and code-app default states through the shared `com.knowtype.preferences` defaults domain. App policy applies those preferences while preserving the Chinese text pipeline; the built-in code-app punctuation default is Chinese unless saved preferences override it. The input-method runtime refreshes saved defaults at new composition/direct symbol boundaries, bypasses the normal reload throttle when the focused app bundle changes, and preserves session-local toggles while preferences and app context are unchanged.

Runtime behavior is represented by `InputMethodRuntimePreferences`: legacy input scheme, candidate page size, candidate layout mode, cloud continuation enablement, local fallback continuation preference for legacy paths, continuation length, and continuation count. These preferences use the same shared defaults domain and are read by the input method at startup and new composition boundaries. The Rime-only settings UI no longer exposes the legacy input-scheme picker; production conversion uses the bundled Rime full-pinyin schema. Defaults preserve the current production behavior: six adaptive candidates per page, adaptive horizontal panel layout, cloud continuation enabled, medium continuation length, and six continuation candidates. If an older preference stores nine candidates per page, adaptive layout caps the effective page size at six; vertical-list mode uses the saved page size.

## AI Runtime Contracts

`KnowTypeAI` exposes:

- `AIRecommendationProviding.recommendation(for:)`
- `AIContextEventRecording.record(_:)`
- `AIRecommendationDiagnosticSink.record(_:)`

`InputControllerCoordinator` depends only on those protocols. Production uses `AIRecommendationRuntime` and `AIContextMemoryRuntime`; tests can inject fakes.

`AIRecommendationRuntime`:

- reads `~/.knowtype/ENV.md` and `~/.knowtype/CORRECTION.md`
- includes `LEXICAL_PROFILE.md` when the coordinator provides a lexical snapshot
- creates default documents when missing
- debounces for 350 ms by default before provider calls
- hard-times out provider requests after 10 seconds by default, independent of the provider profile's network timeout
- caches by raw input, locked prefix, app bundle, locale, ENV hash, CORRECTION hash, and lexical hash
- rejects stale results at the coordinator boundary
- skips cloud requests for too-short context: with a confirmed locked prefix, fewer than two Han characters or fewer than six visible mixed/Latin characters; without a locked prefix, fewer than three visible raw-input characters
- hard-blocks cloud requests only for secret-like raw input or locked prefixes, with diagnostic reason `secret_like_text`
- rejects provider output that repeats or rewrites the locked prefix through local sanitization
- reports sanitizer outcomes as normalized reasons such as `same_as_prefix`, `still_repeats_prefix`, `no_usable_suffix`, and `repeated_prefix_repaired`
- emits privacy-preserving AI diagnostics to macOS unified logging by default under subsystem `com.knowtype.inputmethod.KnowType` and category `ai`

AI diagnostic events carry request/composition identifiers, lengths, counts, elapsed milliseconds, provider name, and normalized reasons only. They must not include raw user input, candidate text, context document contents, provider response bodies, or API keys. Use:

```bash
log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType" && category == "ai"' --style compact
```

`AIContextMemoryRuntime`:

- records only committed text, not marked text
- writes JSONL events under `~/.knowtype/events/typing-events.jsonl`
- archives processed event files under `~/.knowtype/events/processed/`
- summarizes after a batch threshold or interval
- updates only the generated section in `ENV.md`
- normalizes duplicate generated-section markers in loaded snapshots and writes the repaired content back atomically on a best-effort basis; read-only or transient write failures still return the repaired in-memory snapshot
- sanitizes Level 0 protected content before writing logs

`LexicalProfileStore`:

- writes canonical JSON to `~/Library/Application Support/KnowType/AI/lexical-profile.json`
- writes a readable markdown mirror to `~/.knowtype/LEXICAL_PROFILE.md`
- stores only top-K terms, recent commits, source counts, and tone metrics
- never stores full Rime userdb exports, raw provider responses, or API keys

`AIAcceptedLearningStore`:

- appends full accepted AI commit history to
  `~/Library/Application Support/KnowType/AI/accepted-ai-learning.jsonl`
- writes bounded language-habit summary JSON to
  `~/Library/Application Support/KnowType/AI/accepted-ai-summary.json`
- mirrors summary diagnostics to `~/.knowtype/ACCEPTED_AI_LEARNING.md`
- skips records containing secret-like raw input, locked prefix, or accepted text
- feeds only bounded summary terms and recent short accepted commits into
  `LEXICAL_PROFILE.md`; it never writes Rime userdb or calls `sync_user_data`
- emits summary-ready metadata after a delayed summary rebuild is persisted; the
  event contains only schema id, history hash, and counts, not user text
- emits summary-ready metadata only for schemas changed by the current rebuild

`knowtype-accepted-learning-tool` and `scripts/accepted-learning.sh`:

- expose read-only `status`, explicit `rebuild`, and guarded `clear --yes`
  maintenance commands for accepted AI learning
- report only paths, counts, hashes, mtimes, and freshness state; they never
  print raw input, accepted text, locked prefix, or full history
- `clear --yes` deletes only `accepted-ai-learning.jsonl`,
  `accepted-ai-summary.json`, and `ACCEPTED_AI_LEARNING.md`, writes a clear
  marker for running stores, and scrubs accepted-AI terms/source lines and
  matching accepted recent commits from the persistent lexical profile while
  preserving non-AI recent commits and tone data; when accepted history is
  unavailable, markdown-only scrub removes accepted-AI marker/source lines but
  preserves unknown recent commits; it does not delete ENV, CORRECTION,
  provider profiles, Keychain secrets, or Rime userdb
- runtime and maintenance writes, including startup summary repair, use a shared
  lock file so rebuild, clear, startup repair, and accepted-record appends do not
  publish stale summaries across processes
- runtime snapshot reads observe the clear marker before returning accepted-AI
  summaries so active input-method processes stop injecting cleared learning
  without requiring a restart or another accepted record

`AIAcceptedFeedbackStore`:

- appends only verified post-accept edit signals to
  `~/Library/Application Support/KnowType/AI/accepted-ai-feedback.jsonl`
- writes bounded feedback summary JSON to
  `~/Library/Application Support/KnowType/AI/accepted-ai-feedback-summary.json`
- mirrors summary diagnostics to `~/.knowtype/ACCEPTED_AI_FEEDBACK.md`
- feeds request-time `AI_FEEDBACK.md` only as a soft style signal; it is not a
  hard block, does not rewrite locked prefixes, and does not touch Rime userdb
- skips feedback containing secret-like deleted or replacement text
- treats unknown, stale, moved, or unverified cursor ranges as no signal rather
  than negative feedback
- `LexicalProfileRuntime` reloads the persisted lexical profile when its
  in-memory cache still contains accepted-AI source data after accepted learning
  has been cleared, and it filters any remaining accepted-AI terms/source lines
  before building request-time `LEXICAL_PROFILE.md`
- `diagnose-inputmethod.sh --json` includes `userData.acceptedLearning` with the
  same status shape subset used by settings diagnostics

Rime userdb profile refresh is a background-only input-method task. It calls
librime sync as a best-effort freshness step, reads the live active schema from
the Rime session, resolves that schema's `translator/user_dict` or
`translator/dictionary`, scans for that dictionary's
`*.userdb.txt`, and parses standard `code<TAB>text<TAB>c=... d=... t=...` rows
while keeping compatibility with legacy `text<TAB>code<TAB>frequency` fixtures.
Metadata rows identify the lexical text column by treating Rime code columns as
ASCII lowercase code strings, so both `code<TAB>text<TAB>c=...` snapshots and
reversed metadata fixtures avoid persisting code strings as user terms.
Snapshot selection prefers the local `installation_id` sync folder, then chooses
deterministically by root, mtime, and path. Refreshes use a process-wide store
and generation gate shared by IMK sessions. JSON/Markdown bytes are staged
outside the generation gate, and conditional publish re-checks freshness without
holding the gate lock across filesystem operations. If a refresh becomes stale
mid-publish, any promoted profile files are rolled back before the task returns.
AI requests merge persisted `LEXICAL_PROFILE.md` terms only when the stored
profile schema matches the active Rime schema. They do not add the current
composition's Rime candidate page to the lexical profile.

KnowType-specific settings use the InputMethodKit preferences window opened from
the input-method menu as the primary user entry point. `KnowType Settings...`
maps to `showPreferences(_:)`, which creates or reuses
`KnowTypePreferencesWindowController` and hosts the shared SwiftUI settings root.
The opened window uses a macOS-native sidebar/detail layout with grouped form
rows. Settings resources resolve through `SettingsLocalization`: Chinese
preferred languages use `zh-Hans.lproj`, region-specific non-Chinese locales
such as `en-US` fall back to `en.lproj`, and unsupported non-Chinese locales use
English. The input-method menu also exposes `AI Continuation`, log/support
folder shortcuts, the Rime user folder, and About. The standalone settings app
target is a developer preview host, and `KnowType.prefPane` in
`~/Library/PreferencePanes` is a compatibility fallback rather than the default
installation path. Default local installs remove stale compatibility panes;
`--with-prefpane` installs a matching fallback pane when needed. The macOS
Keyboard/Input Sources page remains the enable/select surface and is not treated
as a custom settings host.

## CLI And Script Contracts

`knowtype-demo` is a package-level executable for exercising correction and
commit behavior without installing the input method. It is useful for smoke
checks, but it does not prove IMK host-app behavior.

`knowtype-lexicon-tool install [pack-id] [--directory PATH] [--force]`
installs managed local lexicon packs. The default pack is `rime-pinyin-simp`.
The tool delegates download, SHA256 verification, conversion, atomic writes,
and metadata generation to `ManagedLexiconPackInstaller`. It must not commit
third-party dictionary data to the repository.

`knowtype-inputsource-tool` is the local helper for direct macOS TIS diagnostics,
registration, and cleanup in KnowType scripts:

- `status` emits read-only registration, enabled, selected, and HIToolbox
  preference status.
- `switch-away` moves away from KnowType before bundle replacement without
  starting the installed input-method host. It also removes KnowType rows from
  HIToolbox `AppleSelectedInputSources` so stale selected preferences do not
  relaunch the host while install tooling refreshes registration state.
- `inspect-preferences` and compatibility `dedupe-preferences` report
  duplicate KnowType rows without mutating protected system preference domains.
- `repair-preferences` rewrites only KnowType rows in protected input-source
  preference arrays as an explicit local development fallback for stale `.Mode`
  cache state, parent-only selected/history rows, or stale selected/history rows.
  The default `--add-active` shape restores the enabled parent anchor plus the
  user-selectable `com.knowtype.inputmethod.KnowType.Hans` input mode without
  changing selected preferences. `--include-history` repairs history to `.Hans`
  without moving it ahead of the retained current source unless selected repair
  is also requested. `--include-selected` is reserved for explicit selection
  repair after installed app selection is verified and rewrites selected
  preferences to `.Hans`. `--remove-parent-anchor` is reserved for uninstall
  cleanup after the bundle is gone.
  `--legacy-parent-anchor` is accepted as a deprecated compatibility no-op.
- `purge-legacy --path ...` disables legacy `.Mode` rows and
  refreshes LaunchServices without starting `KnowTypeInputMethodApp`.
- `bootstrap --path ... [--select]` registers the installed bundle, enables the
  parent anchor and visible `.Hans` input mode through TIS APIs, and optionally
  requests helper-local selection of `.Hans`. Default install/repair registration
  uses the installed app CLI context before helper preference repair; explicit
  repair/selection tooling owns user-visible selection.
- `register --path ... [--select]` remains a lower-level manual register path
  for debug use.
- `select [--require-selected]` remains a debug-only helper-local selection path.

Script contracts:

- `scripts/build-inputmethod-bundle.sh` creates `dist/KnowType.app` and must
  package SwiftPM resource bundles required by the local engine.
- `scripts/install-inputmethod.sh` copies the local development bundle to
  `~/Library/Input Methods/KnowType.app`, refreshes LaunchServices, and uses
  `knowtype-inputsource-tool purge-legacy` plus `bootstrap` without launching the
  input-method host or selecting KnowType.
- `scripts/diagnose-inputmethod.sh` is the read-only install status and recent
  log diagnostic path.
- `scripts/select-inputmethod.sh` requests selection through the installed app,
  but selection remains scoped to the active macOS input context and is not proof
  of typing behavior.
- `scripts/accept-inputmethod-local.sh` generates the local acceptance report
  template and only mutates install or selection state when explicit flags are
  passed.
- `scripts/smoke-inputmethod-install.sh` is CI-safe and must not mutate Text
  Input Source state.

## Level 0 And Secret Gate Contract

Level 0 remains the correction/local-protection contract. It prevents correction
from rewriting protected input and preserves protected text for commit in legacy
session-controller paths. Real-time cloud AI recommendation has a narrower hard
block: only secret-like raw input or confirmed locked prefixes produce
`AI 已禁用`.

Level 0 includes:

- URL-like input
- email-like input
- file paths
- command-like input
- code-like snippets
- protected Terminal, iTerm, and Xcode contexts

Technical-token preservation is separate from Level 0 routing. A mixed prose input can preserve `API` or `macOS` while still being eligible for provider continuation.

Normal technical tokens, commands, paths, URLs, and Terminal/iTerm/Xcode app
context do not directly disable real-time AI recommendation. If a Rime
candidate hint contains secret-like text, that hint is filtered without blocking
the rest of the request.
