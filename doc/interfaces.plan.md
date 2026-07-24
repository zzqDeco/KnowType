# KnowType Interfaces

This document records current cross-layer contracts. Provider-specific shapes, UI render details, and host-app quirks should not leak across these boundaries.

## Provider Request

Internal request shape:

```text
LLMRequest {
  task: correction | continuation | contextDigest
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
(`correction` and `continuation`) use a `candidates` array with `text`, `confidence`, and `reason`.
`contextDigest` uses a separate `{ markdown: string }` response and is normalized into an `LLMResponse` candidate
only after strict decoding. OpenAI Chat and Responses prefer `json_schema` with `strict=true`; OpenAI-compatible
endpoints that reject schema fields fall back once to JSON mode and report `structured_schema_unsupported` in
`LLMResponse.diagnostics`. Gemini and Anthropic send native schema hints and also fall back when the endpoint
rejects those fields. Ollama and custom HTTP do not claim provider-enforced schema, but their outputs still pass
through strict local decoding instead of line-based candidate extraction.

Raw OpenAI Responses payloads are accepted only after the adapter confirms a
completed response, traverses every `message` output and `output_text` content
item, and rejects any refusal or incomplete message. All collected text is
decoded as one structured value, so a valid-looking partial item cannot be
accepted independently. Anthropic Messages requests omit `temperature`,
`top_p`, and `top_k` by default; ordinary completion and Settings connection
diagnostics use the same adapter request builder.

Real-time AI recommendation requests use `task: continuation`, `rawInput`, app context, and `contextDocuments["ENV.md"]` / `contextDocuments["CORRECTION.md"]`. `lockedPrefix` is present only for text the user has already confirmed or resolved; unselected Rime candidates are not sent to the provider and must not be promoted into a locked prefix. Background memory updates use `task: contextDigest` with the pending event batch in `rawInput` and the current `ENV.md` as a context document.

Provider prompts are task-specific. Continuation requests distinguish confirmed prefixes from unconfirmed raw input:

- when `lockedPrefix` is present, candidate `text` must be directly appendable after it and must not repeat, paraphrase, translate, rewrite, or otherwise modify the locked prefix
- when `lockedPrefix` is absent, candidate `text` is a full commit-ready recommendation inferred from `rawInput` and context documents

When a non-empty `lockedPrefix` exists, cloud eligibility is gated by that locked prefix alone; otherwise it is gated by raw input length. Runtime output must preserve the original locked-prefix text, including intentional leading or trailing whitespace, and may only use trimmed text for emptiness and sanitizer comparisons. `AI 已禁用` is reserved for secret-like raw input or confirmed locked prefixes. Correction and context digest requests keep separate prompts so continuation examples cannot leak into those tasks. The local prefix-lock sanitizer remains authoritative whenever a locked prefix exists, even when a provider follows the prompt.

## Input Client Compatibility

Host write behavior is selected before each key write:

```text
InputClientWriteMode =
  inlineComposition
  commitOnlyComposition
  asciiPassthrough
  disabled
```

Unknown clients, standard text clients, browsers, editors, IDEs, Electron
shells, and JetBrains-style clients use `inlineComposition` by default, so raw
preedit appears in the focused text field. Terminal, iTerm, MacVim, and
Emacs-style profiles use placeholder carrier during Chinese composition, but
they share the same process-wide input mode as every other host.
Commit-only composition uses a full-width-space
`NSAttributedString` marked-text placeholder with marked attributes to keep the
IMK composition and candidate anchor alive. The host text field sees only that
placeholder; the candidate panel receives the real raw/preedit display text as a
non-selectable preedit row above candidates, then commits with `insertText`.
`Option + /` toggles process-wide text mode and restores linked Chinese/English
punctuation. `Option + .` is a Chinese-mode-only manual punctuation override
that expires on the next text-mode switch. `Shift + Space` toggles the
independent process-wide half-width/full-width state. ASCII mode passes idle
half-width printable input back to the focused app; in full-width mode KnowType
transforms only mapped ASCII characters and space, while unchanged Unicode text
continues through ASCII passthrough. Missing clients use `disabled`; printable
idle input is returned as unhandled before any full-width fast path so a stale
host client is never reused. All write modes keep
replacement ranges as `{NSNotFound, NSNotFound}` unless a future reconversion
feature introduces an explicit owned range.
`InputClientCompositionWriter` is the internal boundary that applies this mode
to inline marked text, placeholder marked text, idle passthrough, and owned
marked-text cleanup. `InputClientWriteCoordinator` remains the lower-level
writer for `setMarkedText`, `insertText`, replacement ranges, and debug logs.

The local punctuator receives `InputPunctuatorContext`. Only Chinese
half-width quote keys ask the IMK adapter for the single UTF-16 unit immediately
before a collapsed caret; English and full-width quote output does not read
document context.
Whitespace and opening punctuation open a quote; text, digits, and closing
punctuation close it. A preceding Chinese quote and unknown context fall back
to session alternation so consecutive quote keys still form an opening/closing
pair. An
idle `.` uses only a client-bound, expected-caret record of the last KnowType
insertion, so an ASCII digit produces `.` even in Chinese punctuation or
full-width mode without reading host document text. Diagnostics record only
the character classification and context source, never document text.

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

ProviderProfilesFile {
  schemaVersion = 2
  revision
  profiles
}
```

Default file-backed profile storage writes canonical `providers.v2.json` under
the user's Application Support `KnowType` directory only on explicit save.
During upgrade, numeric legacy `providers.json` is copied exactly to
`providers.legacy.json`, available credentials are rekeyed, and the legacy path
becomes an incompatible tombstone. Schema-v1 files decode at revision `0`;
unknown future schemas fail closed. Production mutations hold a sidecar `flock`, compare the ViewModel's
expected revision, increment once, and atomically replace the file. Successful
commits emit a privacy-safe cross-process revision signal. Runtime cold-start
paths use the no-create loader, so a genuinely absent provider profile does not
create `Application Support/KnowType` merely because the IMK host was launched.
The process-level runtime registry observes the signal and returns leases with
`revision`, `generation`, opaque `fingerprint`, and optional `provider`. It uses
the file revision only as an eligible-dispatch fallback. A generation change
cancels old lease operations and rejects late results before UI, ENV, or archive
writes.
Unmigrated legacy or missing post-migration canonical state fails closed. The
install migration first publishes a recoverable provisional tombstone and only
marks canonical metadata expected after the canonical file is durable.
Install and rollback invoke these explicit migration, rollback, and downgrade
operations through `knowtype-inputsource-tool`. The input-method app keeps
compatible command-line aliases, but shell tooling does not execute the
installed bundle's main IMK executable because macOS may terminate that process
outside its normal host launch context.

`secretName` resolves through `SecretStore`. On macOS, `KeychainSecretStore`
stores API keys under the `KnowType` service. New key writes use immutable
`knowtype.provider.<profileID>.credential.<UUID>` references. The secret is
written before metadata; failed metadata commits delete the new secret, while
successful commits clean old unreferenced secrets afterward. Existing legacy
references remain readable until the next secret change. Tests and non-UI code
can use in-memory or read-only dictionary stores.

When canonical `providers.v2.json` is missing in a genuinely new store or is
empty, settings and runtime loading share seeded defaults. The default profile
is local OpenAI-compatible at `http://127.0.0.1:8317/v1`, may leave `model`
blank for discovery, and does not embed an API key.
New Anthropic and Gemini templates use `claude-haiku-4-5-20251001` and
`gemini-3.5-flash`. On profile load, the exact retired IDs
`claude-3-5-haiku-latest` and `gemini-1.5-flash` migrate once through the
observed provider-file revision only when the provider kind and official HTTPS
endpoint also match. Anthropic accepts its root and `/v1` base paths; Gemini
remains root-only. Custom proxy paths, hosts, queries, userinfo, fragments,
nonstandard ports, and non-exact model IDs are preserved.

Settings validation rules:

- display name cannot be empty
- base URL must be HTTP(S) with a host and cannot include userinfo or a fragment;
  query parameters remain accepted for runtime compatibility
- provider-specific paths are appended before preserved query items; Gemini
  replaces only its own `key` item
- timeout must be positive
- remote OpenAI-compatible profiles require an explicit model ID
- local OpenAI-compatible profiles may leave model blank for `/v1/models` discovery
- cloud profiles require a new key or an existing non-empty secret
- custom HTTP profiles require body template and response path, but may omit the API key
- custom HTTP placeholders are rendered in one pass over the original template;
  replacement text is never rescanned, and unknown or unclosed placeholders fail
  before a request is sent
- stale ViewModel revisions reject saves and default changes, refresh disk state,
  and preserve the draft
- profile saves publish new settings only after a required new secret and the
  metadata transaction succeed

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
- compare the provider-file baseline before sending and before publishing the
  result; stale baselines refresh saved profiles and preserve the draft
- immutable secret references ensure an E1 snapshot cannot resolve a newer K2
  reference committed for E2

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

Install backups live under `Backups/<backup-id>/`. Manifest schema `2` records
the backup id and creation time plus each included artifact's checksum, bundle
identifier, short version/build, designated signing requirement, and normalized
signing identity. PreferencePane fields are explicitly null when no pane is
included. Rollback validates manifest shape and ID, every recorded field,
`codesign --verify --deep --strict`, the recorded requirement, and staged-copy
checksums before replacing the canonical app or pane. Schema `1` backups fail
closed unless the caller supplies the prominent legacy-only
`--allow-unverified-backup` override; it never bypasses schema `2` failures.
Rollback restores only `KnowType.app` and optional `KnowType.prefPane`, then
refreshes LaunchServices and input-source preferences.

Destructive PreferencePane operations accept only the canonical local
non-symlink `KnowType.prefPane` with
`CFBundleIdentifier=com.knowtype.preferencepane`. A same-name foreign bundle
blocks install, uninstall, explicit rollback, and failed-install recovery.

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
- `InputAIRecommendationSchedulePolicy`: input-method value policy that returns
  either an AI recommendation schedule decision or the skipped AI state plus
  diagnostic stage and reason before provider tasks are started.
- `InputAIRecommendationRuntime`: input-method runtime boundary that owns
  real-time AI request construction, active request ids, generations, task
  cancellation, stale-result diagnostics, and state publication callbacks.
- `InputAIAcceptanceRuntime`: input-method runtime boundary that owns
  post-commit AI accepted-learning records, typing-context events, accepted
  feedback tracking orchestration, and protected/secret gates.
- `AITypingEvent`: committed typing event used by the background memory runtime.
- `AIAcceptedLearningRecord`: local-only JSONL record for an AI recommendation the user explicitly accepted.
- `AIAcceptedLanguageSummary`: bounded accepted-AI term, style, and recent-commit summary used by lexical profile merging.
- `RimeUserDBTextSnapshot`: text export snapshot from Rime user data sync.
- `RimeMaintenanceService`: background owner of explicit `sync_user_data`, userdb snapshot discovery, and idle/manual maintenance policy.
- `LexicalProfileRuntime`: input-method runtime that merges persisted profile terms with recent commits and selection history, schedules background profile refresh from existing userdb snapshots, and clears summary-ready observer state when refreshes are cancelled during controller close.
- `InputLexicalCommitRuntime`: input-method runtime that owns local lexical
  commit/selection side effects, including bounded recent commits,
  selection-history orchestration, lexical profile refresh scheduling, and
  `compositionCommitted` / `candidateSelected` event payload construction.
- `InputSuggestionStateRuntime`: input-method runtime that owns the latest
  `SuggestionResponse`, the raw input that produced it, commit suggestion
  snapshots, current-suggestion checks, and resolved-composition no-provider
  fallback cleanup.
- `InputCompositionStateRuntime`: input-method runtime that owns raw input,
  `CompositionBuffer`, composition id, raw revision, delete count, and pure
  composition-state mutation results.
- `InputCompositionLifecycleRuntime`: input-method runtime that owns
  composition begin/finish plans, first-begin trace-once state, finish reason
  mapping, finished composition id capture, and owned marked-text clear intent.
- `InputCommitApplicationRuntime`: input-method runtime that maps commit
  results to coordinator plans and constructs accepted-feedback, AI acceptance,
  and lexical commit contexts without performing host writes or
  Rime/candidate-panel side effects.
- `InputSelectionHistoryRuntime`: input-method session owner for protected-input
  filtering, recent selection history, `candidateSelected` event payloads, and
  persistence delegation for prefix candidate choices.
- `LexicalContextSnapshot`: top-K lexical/tone summary rendered as `LEXICAL_PROFILE.md` and hashed into AI cache keys.
- `SuggestionResponse`: UI-facing snapshot containing `prefixCandidates`, `lockedPrefix`, `continuationCandidates`, and `latencyMs`.
- `ConversionEngineSnapshot`: Rime-facing snapshot containing raw input, preedit, current-page candidates, highlighted index, page size, page number, page-end state, and engine name.
- `InputCandidatePanelPublicationRuntime`: input-method runtime boundary that
  owns candidate-panel state publication, async stale-snapshot gating,
  visibility reasons, delayed re-anchor generation, and panel diagnostics.
- `InputNativeCandidateNavigationRuntime`: input-method runtime boundary that
  owns displayed native selection state, panel-selection mapping, stable native
  index matching, hover highlight, numeric current-page selection, paging, and
  boundary paging decisions.
- `CandidatePanelFrame`: candidate-panel presentation intent with composition id, raw revision, raw length, anchor source, panel model, and explicit visibility reason.
- `AIRecommendationPatch`: AI slot-only update guarded by request id, generation, composition id, raw revision, and raw input.

Raw input is tracked outside `SuggestionResponse` by
`InputSuggestionStateRuntime`, because the UI-facing suggestion snapshot remains
focused on candidates and latency rather than identity. Protection metadata
lives on correction candidates, locked prefixes, and protected ranges rather
than on the top-level suggestion response.
The active composition raw input itself is owned by
`InputCompositionStateRuntime`; suggestion state stores only the raw identity of
the suggestion currently being published or committed.

Core correction and traditional-input candidates may carry `rawRange` and `segments` for offline/session tests. The production IMK coordinator no longer generates segment candidates from `TraditionalInputEngine`; Rime candidates are treated as whole-prefix candidates over the current raw input.

`InputContext.userSelectionHistory` is a local-only ranking hint. It may reorder prefix candidates that were already generated by the local correction engine, but it must not create new candidates and must not be serialized into provider requests. The IMK frontend may persist this history locally in `user-selection-history.json`; `InputSelectionHistoryRuntime` keeps the active process's recent selection cache separate from the loaded durable log, and provider adapters still receive only `LLMRequest`.

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

Input-method presentation maps `SuggestionResponse` into compact candidate rows
through `CandidatePanelRowBuilder`, which is shared by selection state and
rendering:

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
commit behavior. Mouse hover, click commit, keyboard selection, accessibility
selected children, and VoiceOver press all consume the same
`CandidatePanelSelection` values so pointer and accessibility commits match
keyboard commits. Disabled/status rows have no press action.

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
- `InputNativeCandidateNavigationRuntime` is the owner of Rime navigation
  decisions above the engine boundary. It may call highlight, current-page
  select, PageUp, and PageDown keys, but conversion result side effects, host
  writes, and candidate-panel publication stay outside the runtime.

## IMK Client Writes

KnowType treats host-reported `markedRange` as advisory. It may be used by
candidate anchoring and diagnostics, but ordinary text writes must not use it as
a replacement range because some host apps can report stale ranges after fast
Space/Return or focus changes.

Current write contract:

- composing `setMarkedText`, clear-marked `setMarkedText("")`, ordinary
  `insertText` commits, and idle Space/digit passthrough all use
  `NSRange(location: NSNotFound, length: NSNotFound)`
- inline hosts receive attributed marked text while composition is active
- terminal-style or override commit-only hosts receive a full-width-space
  attributed placeholder marked text while composition is active; raw pinyin and
  candidate text are not written inline
- commit-only preedit is a candidate-panel display concern: it is not
  selectable, does not receive numeric shortcuts, and must not enter commit text
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
- Rime-compatible paging punctuation (`-`/`=`, `,`/`.`) first attempts `.pageUp`/`.pageDown`; when the native snapshot does not change, comma and period fall back to the local punctuator commit path so page shortcuts do not swallow `，`/`。` at page boundaries.
- Other composing ASCII symbols are offered to Rime before KnowType punctuation fallback so schema keys such as apostrophe, semicolon, and slash can be handled by the engine.
- Explicit `PageUp`/`PageDown` are forwarded to the native engine whenever composition is active, even if the custom panel is hidden because anchoring failed.
- Rime initialization failure produces `engineName: rime-unavailable` and no candidates. The coordinator keeps raw input and raw commit usable instead of falling back to the retired local converter.
- xctest processes use temporary Rime user/log directories so tests do not lock or mutate the user's live Rime DB.
- The hot path emits `InputFrame`/`CandidatePanelFrame`-style state and side-effect events. It must not call AI providers,
  lexical profile write APIs, userdb sync, or candidate-panel AppKit APIs directly. Lexical commit/selection facts go through
  `InputLexicalCommitRuntime`, which may schedule refresh from bounded local snapshots but does not run userdb sync. Composition lifecycle plans go through
  `InputCompositionLifecycleRuntime`, commit choices go through
  `InputCommitDecisionRuntime`, and commit side-effect contexts go through
  `InputCommitApplicationRuntime` before the coordinator executes order-sensitive host writes and lifecycle cleanup. Real-time AI provider calls go through
  `InputAIRecommendationRuntime`, which publishes only AI slot state after stale-result guards pass.

Candidate panel sizing is measurement-first. `CandidatePanelRenderer` owns row semantics only; the
`CandidatePanelLayoutEngine` measures visible rows, chooses horizontal layout for 4-6 complete candidates when
possible, switches to vertical layout for long phrases or a fixed preedit row, and returns the final panel size, origin, row frames, and
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
on commit, cancel, deactivate, close, reset, and native composition end. Candidate-panel publication is frame-based
and owned by `InputCandidatePanelPublicationRuntime`: updates carry
`CandidatePanelVisibilityReason`, composition id, raw revision, raw length, and
anchor source through `CandidatePanelPresenter`. Stale suggestions, delayed
reanchors, and AI patches must not make the panel visible after composition
teardown. Anchor source `.none` remains an undisplayable layout-impossible frame
rather than an explicit hide path. A transient empty Rime snapshot does not hide
the panel while KnowType still has non-empty raw input; the presenter keeps a
raw/preedit fallback frame until Rime context recovers or composition ends. With
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
that include the visible shortcut and candidate text; ready AI labels include `AI 推荐`; their press action forwards
the retained selection through the normal commit handler. Disabled AI status rows use static-text semantics and do
not press. Selection changes post focused-element and selected-children notifications. Trackpad scroll deltas
accumulate to at most one page action per began-to-ended gesture and momentum is ignored; phase-less mouse-wheel
events use a 120 ms paging cooldown. Screenshot
regression tests render fixed examples to PNG baselines under `Tests/KnowTypeInputMethodTests/__Snapshots__/`.

`CompositionBuffer` keeps `rawInput`, resolved segments, active range, display text, and commit text separate for legacy/session tests. The production IMK path no longer generates local segment candidates; Rime owns composition and candidate commit for Chinese input.

## Candidate Geometry

Candidate panel movement consumes `CandidateAnchorResult`. UI code should not use pointer location as a moving fallback.

Resolver source priority:

1. at most four deduplicated marked and selected `firstRect` ranges
2. unexpired last usable anchor scoped by composition, app, and an unambiguous
   current screen
3. at most four deduplicated strategic IMK-inline line-height positions
4. one Accessibility focused-range resolve when available, throttled for 100
   ms by composition and app from the actual monotonic attempt time
5. an otherwise valid scoped cache deferred by ambiguous multi-screen topology
6. safe screen fallback inside the visible frame

The resolver accepts zero-width caret rects with valid height and rejects
zero-height, non-finite, offscreen, or stale cross-composition anchors. Anchor
diagnostics contain only probe count, source, scope metadata, and rejection
reason; they do not include user text or raw geometry.

## Shortcut Contract

- `Space` commits the highlighted/current Rime candidate for the current raw input.
- with no active composition, `Space` inserts U+0020 in half-width mode or U+3000 in full-width mode.
- when Rime is unavailable, `Space` commits raw input instead of blocking to compute hidden local candidates.
- `1...9` select Rime current-page candidates during native composition, independent of candidate-panel visibility.
- with no active composition, `0...9` are inserted as half-width or full-width digits according to the process width and do not open the candidate panel.
- `Return` / `Enter` commits the original raw composition.
- `Tab` commits the AI recommendation only when the AI slot is ready; pending, unavailable, disabled, or ineligible AI keeps the composition.
- `Tab` does not trigger AI continuation while the composition is in a legacy partial-segment state.
- `0` commits raw composition when correction candidates are visible.
- visible numeric shortcuts commit rows on the current Rime candidate page only; after the AI slot, native alternatives keep their visible row numbers.
- unmatched digit keys in native composition are consumed instead of appending raw digits; outside native composition, unmatched digits continue composing as literal digits.
- plain punctuation is offered to Rime first while composing; if Rime declines,
  `InputPunctuatorRuntime` returns only `InputSymbolRule.direct(finalText)` or
  `.candidates(trigger:outputs:)`. Chinese punctuation mode maps sentence
  punctuation, context-selected Chinese quotes, ellipsis, em dash, bracket
  pairs, and ambiguous entries such as `/` for dunhao. Full-width mode
  transforms printable ASCII `!...~` and U+0020, but never control characters,
  Tab, or newline. Deprecated public `InputPunctuatorDecision` adapters remain
  source-compatible, but production code does not use `passThrough`.
- `InputActiveSessionRuntime` owns one `none`, `text`, or `symbol` session.
  Starting candidates from text uses a full composition commit, not Space, so
  native partial-segment commits cannot leave text active; a symbol session is
  created only after the text lifecycle reaches idle. Symbol state owns
  immutable candidates and selection, while `CandidatePanelState` is only a
  render projection. External runtime-preference refreshes republish that
  projection while the symbol session remains active.
- `Space`, Return, valid visible numbers, and mouse selection commit the current
  symbol. Escape and Backspace cancel without deleting existing host text.
  Repeating the same trigger advances to the next candidate. Other printable
  input commits the selected symbol, clears the session, and replays the
  original intent once from idle. Invalid number shortcuts follow the same
  commit-and-replay rule.
- Raw key events and AppKit responder commands share symbol navigation.
  Navigation is consumed at clamped boundaries without changing host text,
  caret, or selection. Command/Control shortcuts cancel and return unhandled.
  Explicit commit commits directly. Click-outside and deactivate commit only
  when the current host identity, selected range, marked range, and bundle
  match the context captured when the symbol session began; changed or missing
  host context cancels. Reset, close, and input-mode generation changes also
  cancel. Symbol sessions do not trigger AI requests, Rime symbol mutation,
  prefix learning, or marked-text preview in this slice.
- Command/Control key-down is a host-shortcut intent. If a symbol-candidate
  session is active, KnowType cancels its session and overlay before returning
  the key to the host; key-up remains ignored and flags-changed remains a
  separate non-commit intent.
- `Option + .` toggles a manual Chinese/English punctuation override only while
  process-wide text mode is Chinese. In ASCII mode it is a state no-op that
  republishes the current status.
- `Option + /` toggles process-wide Chinese/ASCII text mode, synchronizes
  punctuation to Chinese/English, clears the manual override, and publishes a
  transient mode-status row shared across apps.
- `Shift + Space` toggles process-wide half-width/full-width characters without
  changing text or punctuation. Plain `Space` still commits candidates or
  inserts a width-appropriate space. The transient row is cleared before
  the next real input key publishes composition, symbol candidates, commit, or
  passthrough output, so it does not remain mixed into active candidate content.
- `Option + 1` commits the ready AI recommendation explicitly; when AI is pending, unavailable, disabled, ineligible, or idle, it is consumed without committing legacy continuations.
- `Option + 2...9` commits legacy continuation rows when they are present.

Input attributes are represented by `InputModeState`: text mode, punctuation
language, and symbol width are separate fields. `InputModeStateMachine` adds
punctuation source and generation, while `ProcessInputModeStateRuntime` shares
one state across all controllers in the host process. The initial state is
linked Chinese input and Chinese punctuation with the saved global width.
Changing app or window does not reload mode. A host restart creates a fresh
linked Chinese state. `InputModePreferences` persists only
`input.global.symbolWidth`; legacy normal/code app fields remain readable but
do not influence runtime mode.

`RimeConversionEngine` maps every process snapshot to native session options:
Chinese/ASCII text controls `ascii_mode`, Chinese/English punctuation controls
`ascii_punct`, and half/full width controls `full_shape`. The desired snapshot
is cached without creating Rime during cold start, then applied after schema
selection for every new session and whenever generation changes. The C bridge
checks `RimeApi.data_size` and null option pointers so older librime builds fail
closed rather than reading beyond their API struct.

The local quote fallback reads the preceding document character only on quote
keys. Whitespace and Unicode opening punctuation choose an opening quote;
text, digits, and closing punctuation choose a closing quote. Unknown context
uses session alternation. External delete, focus or selection changes, and mode
generation changes reset alternation. The ASCII-digit-plus-period exception is
evaluated from the last recorded KnowType insertion before punctuation and width
conversion and therefore remains `.` without a period-key document read.

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
- rebuilds cache and health state for each provider generation; an internal
  stale-generation state clears its own normal pending slot to `.idle`, while an
  older stale request cannot clear a newer request
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
- requires a usable provider lease before a registry-backed event is appended,
  so text entered without an available provider is not retained for later upload
- writes JSONL events under `~/.knowtype/events/typing-events.jsonl`
- limits `rawInput` and `committedText` to 2,048 Unicode scalars before writing
- caps pending data at 500 events or 1 MiB; overflow atomically keeps the newest
  data within a 450-event/768 KiB compaction target
- claims no more than the oldest 50 events or 256 KiB for one provider digest,
  while always allowing one event to make progress
- archives processed event files under `~/.knowtype/events/processed/` and,
  after successful digests only, keeps at most 7 days, 100 files, and 10 MiB
- summarizes after a batch threshold or interval
- updates only the generated section in `ENV.md`
- normalizes duplicate generated-section markers in loaded snapshots and writes the repaired content back atomically on a best-effort basis; read-only or transient write failures still return the repaired in-memory snapshot
- sanitizes Level 0 protected content before writing logs
- is shared across all controllers in the process, so one pending snapshot
  starts at most one digest request
- updates ENV and archives a pending prefix only while both its provider lease
  and snapshot claim remain current; later appended events stay pending
- uses a path-shared process inventory for count/byte/protection gates, so
  below-threshold and unchanged-generation cooldown paths do not decode JSONL
- emits count-only `context_event_truncated`, `context_backlog_trimmed`,
  `context_digest_deferred`, and `context_archive_pruned` diagnostics

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
the input-method menu as the primary user entry point. The localized settings
menu item maps to `showPreferences(_:)`, which creates or reuses
`KnowTypePreferencesWindowController` and hosts the shared SwiftUI settings root.
The opened window uses a macOS-native sidebar/detail layout with grouped form
rows. Settings resources resolve through `SettingsLocalization`: default UI
lookup checks `zh-Hans.lproj` first, then preferred languages, then `en.lproj`.
Explicit English locale queries still return the English resource path. The
input-method menu also exposes localized AI continuation, log/support folder
shortcuts, the Rime user folder, and About. The standalone settings app
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
  repair after helper-local selection is verified and rewrites selected
  preferences to `.Hans`. `--remove-parent-anchor` is reserved for uninstall
  cleanup after the bundle is gone.
  `--legacy-parent-anchor` is accepted as a deprecated compatibility no-op.
- `purge-legacy --path ...` disables legacy `.Mode` rows and
  refreshes LaunchServices without starting `KnowTypeInputMethodApp`.
- `bootstrap --path ... [--select]` registers the installed bundle, enables the
  parent anchor and visible `.Hans` input mode through TIS APIs, and optionally
  requests helper-local selection of `.Hans`. Default install/repair
  registration and preference repair remain helper-only; explicit
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
- `scripts/select-inputmethod.sh` requests selection through the standalone helper,
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
