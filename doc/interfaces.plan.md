# KnowType Interfaces

This document records current cross-layer contracts. Provider-specific shapes, UI render details, and host-app quirks should not leak across these boundaries.

## Provider Request

Internal request shape:

```text
LLMRequest {
  task: correction | continuation | contextDigest | polish
  lockedPrefix?: string
  rawInput?: string
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
}
```

Provider adapters must not expose native OpenAI, Anthropic, Gemini, Ollama, or custom HTTP response shapes outside `KnowTypeProviders`.

Real-time AI recommendation requests use `task: continuation`, `lockedPrefix`, `rawInput`, app context, and `contextDocuments["ENV.md"]` / `contextDocuments["CORRECTION.md"]`. Background memory updates use `task: contextDigest` with the pending event batch in `rawInput` and the current `ENV.md` as a context document.

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

Default file-backed profile storage writes `providers.json` under the user's Application Support `KnowType` directory.

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
- `SuggestionResponse`: UI-facing snapshot containing `prefixCandidates`, `lockedPrefix`, `continuationCandidates`, and `latencyMs`.
- `ConversionEngineSnapshot`: Rime-facing snapshot containing raw input, preedit, current-page candidates, highlighted index, page size, page number, and engine name.

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

Ready AI recommendations are selectable and keep the second numeric shortcut. Pending, unavailable, and ineligible AI
states are rendered as disabled status rows: they preserve the visible slot but have no selection identity, no numeric
shortcut, and no commit behavior. Mouse hover, click commit, keyboard selection, and accessibility selected children all
consume the same `CandidatePanelSelection` values so click commits match keyboard commits.

## Rime Hot Path

`KnowTypeConversionEngine` is the IMK boundary for base conversion. `RimeConversionEngine` is the production implementation:

- `process(.text)`, `.space`, `.selectCandidateOnCurrentPage`, `.pageUp`, and `.pageDown` call the native Rime session synchronously.
- `ConversionEngineSnapshot.suggestionResponse` maps only the current Rime page into prefix candidates; full candidate-list iteration is not part of the key path.
- Numeric shortcuts select the displayed current-page candidate with `select_candidate_on_current_page`.
- Rime-compatible paging punctuation (`-`/`=`, `,`/`.`) first attempts `.pageUp`/`.pageDown`; when the native snapshot does not change, the key falls back to the normal punctuation commit path so page shortcuts do not swallow punctuation at page boundaries.
- Explicit `PageUp`/`PageDown` are forwarded to the native engine whenever composition is active, even if the custom panel is hidden because anchoring failed.
- Arrow navigation moves selection inside the current Rime page first. At a page edge, left/up attempts `.pageUp` and right/down attempts `.pageDown` so the custom panel behaves like a single paged candidate list even though snapshots contain only the current Rime page.
- Rime initialization failure produces `engineName: rime-unavailable` and no candidates. The coordinator keeps raw input and raw commit usable instead of falling back to the retired local converter.
- xctest processes use temporary Rime user/log directories so tests do not lock or mutate the user's live Rime DB.

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
This keeps the panel above Spotlight and search-like overlays while avoiding private APIs, screen-saver level, or
shielding levels. The visual style uses compact rows, `hudWindow` material, dynamic system colors, and continuous
corners so it stays close to macOS native candidate panels.

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
- when Rime is unavailable, `Space` commits raw input instead of blocking to compute hidden local candidates.
- `1` commits the first Rime candidate when visible.
- `Return` / `Enter` commits the original raw composition.
- `Tab` commits the AI recommendation only when the AI slot is ready; pending, unavailable, disabled, or ineligible AI keeps the composition.
- `2` commits the ready AI recommendation when the AI slot is visible.
- `Tab` does not trigger AI continuation while the composition is in a legacy partial-segment state.
- `0` commits raw composition when correction candidates are visible.
- visible numeric shortcuts commit rows on the current Rime candidate page only; after the AI slot, native alternatives keep their visible row numbers.
- unmatched digit keys continue composing as literal digits.
- plain punctuation commits the current composition display plus punctuation, or inserts punctuation directly with no composition.
- `Option + .` toggles Chinese/English punctuation for the active controller session.
- `Option + number` commits prefix plus the globally mapped continuation.
- `Option + R` requests polish and may rewrite the prefix.

Input attributes are represented by `InputModeState`: text mode, punctuation language, and symbol width are separate fields, so half-width punctuation does not imply ASCII text mode. `InputModePreferences` persists normal-app and code-app default states through the shared `com.knowtype.preferences` defaults domain. App policy applies those preferences while preserving the Chinese text pipeline; the built-in code-app punctuation default is Chinese unless saved preferences override it. The input-method runtime refreshes saved defaults at new composition/direct symbol boundaries and preserves session-local toggles while preferences are unchanged.

Runtime behavior is represented by `InputMethodRuntimePreferences`: legacy input scheme, candidate page size, candidate layout mode, cloud continuation enablement, local fallback continuation preference for legacy paths, continuation length, and continuation count. These preferences use the same shared defaults domain and are read by the input method at startup and new composition boundaries. The Rime-only settings UI no longer exposes the legacy input-scheme picker; production conversion uses the bundled Rime full-pinyin schema. Defaults preserve the current production behavior: six adaptive candidates per page, adaptive horizontal panel layout, cloud continuation enabled, medium continuation length, and six continuation candidates. If an older preference stores nine candidates per page, adaptive layout caps the effective page size at six; vertical-list mode uses the saved page size.

## AI Runtime Contracts

`KnowTypeAI` exposes:

- `AIRecommendationProviding.recommendation(for:)`
- `AIContextEventRecording.record(_:)`

`InputControllerCoordinator` depends only on those protocols. Production uses `AIRecommendationRuntime` and `AIContextMemoryRuntime`; tests can inject fakes.

`AIRecommendationRuntime`:

- reads `~/.knowtype/ENV.md` and `~/.knowtype/CORRECTION.md`
- creates default documents when missing
- debounces before provider calls
- hard-times out provider requests
- caches by locked prefix, app bundle, locale, ENV hash, and CORRECTION hash
- rejects stale results at the coordinator boundary
- rejects provider output that repeats or rewrites the locked prefix through local sanitization

`AIContextMemoryRuntime`:

- records only committed text, not marked text
- writes JSONL events under `~/.knowtype/events/typing-events.jsonl`
- archives processed event files under `~/.knowtype/events/processed/`
- summarizes after a batch threshold or interval
- updates only the generated section in `ENV.md`
- sanitizes Level 0 protected content before writing logs

KnowType-specific settings are hosted by three supported entry points: the standalone settings app, `KnowType.prefPane` in `~/Library/PreferencePanes`, and the InputMethodKit preferences window opened from the input-method menu. The macOS Keyboard/Input Sources page remains the enable/select surface and is not treated as a custom settings host.

## CLI And Script Contracts

`knowtype-demo` is a package-level executable for exercising correction and
commit behavior without installing the input method. It is useful for smoke
checks, but it does not prove IMK host-app behavior.

`knowtype-lexicon-tool install [pack-id] [--directory PATH] [--force]`
installs managed local lexicon packs. The default pack is `rime-pinyin-simp`.
The tool delegates download, SHA256 verification, conversion, atomic writes,
and metadata generation to `ManagedLexiconPackInstaller`. It must not commit
third-party dictionary data to the repository.

`knowtype-inputsource-tool` is the local helper for direct macOS TIS diagnostics
and cleanup in KnowType scripts:

- `status` emits read-only registration, enabled, selected, and HIToolbox
  preference status.
- `switch-away` is a debug fallback; install scripts use the installed app's
  command-line path to move away from KnowType before bundle replacement.
- `inspect-preferences` and compatibility `dedupe-preferences` report
  duplicate KnowType rows without mutating protected system preference domains.
- `repair-preferences` rewrites only KnowType rows in protected input-source
  preference arrays as an explicit local development fallback for stale `.Mode`
  cache state or a missing third-party parent anchor.
- `register --path ... [--select]` manually registers and optionally selects the
  installed bundle through TIS APIs only for debug use.
- `select [--require-selected]` remains a debug-only helper-local selection path.

Script contracts:

- `scripts/build-inputmethod-bundle.sh` creates `dist/KnowType.app` and must
  package SwiftPM resource bundles required by the local engine.
- `scripts/install-inputmethod.sh` copies the local development bundle to
  `~/Library/Input Methods/KnowType.app` and runs app-local purge plus
  activation commands.
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

## Level 0 Contract

Level 0 input must not call cloud providers. The session controller routes protected input through a no-provider pipeline, clears continuation candidates, and preserves protected text for commit.

Level 0 includes:

- URL-like input
- email-like input
- file paths
- command-like input
- code-like snippets
- protected Terminal, iTerm, and Xcode contexts

Technical-token preservation is separate from Level 0 routing. A mixed prose input can preserve `API` or `macOS` while still being eligible for provider continuation if it does not match a protected context.
