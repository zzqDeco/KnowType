# KnowType Interfaces

This document records current cross-layer contracts. Provider-specific shapes, UI render details, and host-app quirks should not leak across these boundaries.

## Provider Request

Internal request shape:

```text
LLMRequest {
  task: correction | continuation | polish
  lockedPrefix?: string
  rawInput?: string
  locale: zh-CN | en-US | mixed
  appContext?: string
  maxCandidates: number
  lengthLevel?: short | medium | long
  outputSchema: json
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
- `SuggestionResponse`: UI-facing snapshot containing `prefixCandidates`, `lockedPrefix`, `continuationCandidates`, and `latencyMs`.

Raw input is tracked outside `SuggestionResponse` by the input-method session, for example through stale-result guards such as `latestSuggestionRawInput`. Protection metadata lives on correction candidates, locked prefixes, and protected ranges rather than on the top-level suggestion response.

Correction and traditional-input candidates may also carry `rawRange` and `segments`. Candidates without segment metadata are treated as legacy whole-prefix candidates. Candidates with segment metadata are interpreted as edits over the current raw input rather than immediate committed text.

`InputContext.userSelectionHistory` is a local-only ranking hint. It may reorder prefix candidates that were already generated by the local correction engine, but it must not create new candidates and must not be serialized into provider requests. The IMK frontend may persist this history locally in `user-selection-history.json`; provider adapters still receive only `LLMRequest`.

`TraditionalInputEngine()` loads `TraditionalInputSeedLexicon` first. `TraditionalInputEngine(additionalLexiconEntries:)` is the public extension point for larger local lexicons. The engine trims and lowercases injected pinyin tokens, ignores empty rows, merges duplicate pinyin keys through its private index, and uses those entries for both spaced and compact pinyin parsing.

`TraditionalInputLexiconResourceLoader` accepts JSON resources shaped as `[TraditionalInputLexiconEntry]` or TSV rows in `pinyin<TAB>text<TAB>confidence` form. TSV confidence is optional and defaults to `0.72`. The loader returns typed errors for invalid UTF-8, malformed rows, empty text, or out-of-range confidence.

`TraditionalInputLexiconCatalogLoader` accepts named resources, loads each one independently, preserves valid entries, and returns diagnostics for failed resources. `TraditionalInputLexiconCatalog.makeEngine()` is the preferred handoff into `TraditionalInputEngine`.

`TraditionalInputLexiconFileSource` infers `.json` and `.tsv` formats from file extensions, reads explicit file lists or sorted directory contents, skips hidden directory entries and known managed-pack metadata filenames, and reports unsupported or unreadable files through catalog diagnostics.

`TraditionalInputLexiconDirectoryResolver` resolves `KNOWTYPE_LEXICON_DIR`, colon-separated `KNOWTYPE_LEXICON_DIRS`, and `~/Library/Application Support/KnowType/Lexicons`, trimming empty paths and de-duplicating standardized file paths while preserving order.

`InputMethodLexiconRuntime` uses the shared resolver, then creates the `TraditionalInputEngine` used by the input-method pipeline. Missing directories are ignored so a fresh install keeps using only the bundled seed lexicon. `defaultEngine()` rebuilds from the currently resolved directories on each request rather than returning a process-wide stale snapshot.

`InputMethodLexiconRuntime.snapshot()` reports each configured directory's existence and supported JSON/TSV resource files with modification metadata. The IMK frontend uses that snapshot to refresh its runtime engine at the start of a new composition when local lexicon resources changed, without changing active marked text mid-composition.

`ManagedLexiconPackInstaller` currently supports the recommended `rime-pinyin-simp` pack. It downloads the pinned Rime source dictionary, verifies the expected SHA256, converts Rime rows shaped as `text<TAB>pinyin<TAB>weight?` into KnowType TSV, writes the TSV atomically, and writes metadata containing source, version, checksum, license, entry count, and install date. It refuses to overwrite an existing output file unless `force` is true.

`LexiconSettingsViewModel` uses the shared resolver for settings status. It uses `TraditionalInputLexiconFileSource` for entry counts and diagnostics, can create missing directories or a non-overwriting `knowtype-sample.tsv`, and can install the recommended managed lexicon pack on explicit user action. It displays `*.metadata.json` pack metadata but does not treat metadata files as lexicon resources.

Input-method presentation maps `SuggestionResponse` into compact candidate rows:

- raw input is shown only when no prefix or continuation suggestion exists
- prefix candidates are first-class selectable rows
- full candidates cover the entire raw buffer and commit as complete Chinese text
- segment candidates cover part of the raw buffer and update the active composition without inserting committed text
- continuation candidates commit as `locked prefix + continuation`
- rows are paged through `CandidatePanelPagingState`, currently 9 visible rows per page
- when a provider is configured, immediate local output may omit fallback continuation rows until provider output arrives

Candidate panel sizing is measurement-first. `CandidatePanelRenderer` owns row semantics only; the
`CandidatePanelLayoutEngine` measures visible rows, chooses horizontal layout for 4-6 complete candidates when
possible, switches to vertical layout for long phrases, and returns the final panel size, origin, row frames, and
per-row text limits used by the AppKit view. The layout plan must keep shortcut/selectable rows in sync with
rendered rows; constrained vertical layouts compress row height and spacing instead of dropping rows after
shortcuts are assigned.

`CompositionBuffer` keeps `rawInput`, resolved segments, active range, display text, and commit text separate. While composing `nishishei`, marked text displays `nishishei`; selecting the segment `你` changes marked text to `你shishei` without calling `insertText`.

## Candidate Geometry

Candidate panel movement consumes `CandidateAnchorResult`. UI code should not use pointer location as a moving fallback.

Resolver source priority:

1. marked and selected `firstRect` ranges
2. insertion-point `firstRect`
3. line-height rectangles
4. Accessibility focused-range bounds when available
5. same-composition scoped last usable anchor

The resolver accepts zero-width caret rects with valid height and rejects zero-height, non-finite, offscreen, or stale cross-composition anchors.

## Shortcut Contract

- `Space` commits the selected prefix.
- with a selected segment candidate, `Space` applies that segment and commits only after all non-whitespace raw input is resolved.
- `Return` / `Enter` commits the original raw composition.
- `Tab` commits selected prefix plus first or selected continuation.
- `Tab` does not trigger continuation while the composition is only partially segmented.
- `0` commits raw composition when correction candidates are visible.
- visible numeric prefix shortcuts commit rows on the current candidate page only.
- unmatched digit keys continue composing as literal digits.
- plain punctuation commits composition plus punctuation, or inserts punctuation directly with no composition.
- `Option + .` toggles Chinese/English punctuation for the active controller session.
- `Option + number` commits prefix plus the globally mapped continuation.
- `Option + R` requests polish and may rewrite the prefix.

Input attributes are represented by `InputModeState`: text mode, punctuation language, and symbol width are separate fields, so half-width punctuation does not imply ASCII text mode. `InputModePreferences` persists normal-app and code-app default states through the shared `com.knowtype.preferences` defaults domain. App policy applies those preferences while preserving the Chinese text pipeline. The input-method runtime refreshes saved defaults at new composition/direct symbol boundaries and preserves session-local toggles while preferences are unchanged.

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
