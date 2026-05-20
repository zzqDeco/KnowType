# KnowType Architecture

KnowType is split into focused package layers:

- `KnowTypeCore`: product rules, correction, protected-input detection, prefix locking, and continuation sanitization.
- `KnowTypeProviders`: provider profile resolution, HTTP adapters, model discovery, and response normalization.
- `KnowTypeAI`: non-blocking AI recommendation, context-memory, correction-instruction, and provider-health runtimes.
- `KnowTypeInputMethod`: macOS input-method integration, marked text, key behavior, candidate state, and candidate-window presentation.
- `KnowTypeSettingsUI`: reusable SwiftUI settings for provider profiles, runtime preferences, privacy, local install guidance, and local lexicon status.
- `KnowTypeSettingsApp` / `KnowTypePreferencePane`: hosts for the shared settings UI.

The product boundary is strict: correction may refine the prefix, but continuation may only append text after the locked prefix. Explicit polish is the only rewrite path.

## Input Pipeline

```text
raw input
  -> RimeConversionEngine / librime session
  -> current-page Rime candidates
  -> IMK marked text / candidate panel
  -> KnowTypeAI recommendation slot
  -> commit
```

Level 0 protected input exits through the no-provider path. It must not call cloud providers and must not publish cloud continuation candidates. The production IMK hot path no longer uses the clean-room `TraditionalInputEngine` as a Chinese conversion fallback; when Rime is unavailable, KnowType keeps raw input usable and reports degraded conversion state instead of synthesizing hidden local candidates.

## Core Layer

`KnowTypeCore` owns model-neutral behavior:

- `TextProtection` detects Level 0 input such as URLs, emails, paths, commands, code-like snippets, and protected app contexts.
- `TraditionalInputEngine` provides clean-room MVP pinyin decoding with compact segmentation, indexed lexicon lookup, typo normalization, same-pinyin candidates, partial-syllable handling, and initial abbreviations.
- `TraditionalInputEngine` is retained for core/offline tests, package-level demos, and lexicon tooling, but it is retired from the production IMK key path.
- `TraditionalInputEngine` raw-range segment metadata is legacy/offline behavior; the production IMK frontend no longer generates or applies those segment candidates.
- `TraditionalInputSeedLexicon` loads the clean-room seed lexicon from a bundled TSV resource instead of embedding the table in Swift source.
- `TraditionalInputEngine` can also be initialized with authorized local lexicon entries. Those entries use the same private index as the seed lexicon, so larger dictionaries, future bundled resources, and local user lexicons do not need a separate parser path.
- `TraditionalInputLexiconResourceLoader` parses audited JSON or TSV lexicon resources into the same entry shape before they enter the engine.
- `TraditionalInputLexiconCatalogLoader` composes multiple local resources, keeps valid entries when one resource fails, and records per-resource diagnostics for settings or debug UI.
- `TraditionalInputLexiconFileSource` reads JSON/TSV resources from explicit files or a directory, then hands them to the catalog path.
- `ManagedLexiconPackInstaller` can install the recommended Rime Pinyin Simplified pack by downloading a pinned Apache-2.0 source, verifying SHA256, converting it to local TSV, and writing pack metadata beside the TSV.
- `CorrectionEngine` can boost generated prefix candidates from local user selection history without adding new dictionary entries or sending selection data to providers.
- English and mixed-input paths preserve technical tokens such as `API`, `JSON`, `FastAPI`, `iOS`, `macOS`, and `InputMethodKit`.
- `CorrectionEngine` may ask a configured provider for unknown pinyin-shaped input only in legacy correction/demo paths when `TraditionalInputEngine` reports no local candidate and the input is not protected technical or English text.
- `PrefixContinuationEngine` sanitizes provider output so continuation candidates do not repeat or rewrite the locked prefix.

Current Chinese-input coverage includes examples such as:

- `wo jue de zhege fagnan -> 我觉得这个方案`
- `wojuedezhegefagnan -> 我觉得这个方案`
- `nishishei -> 你是谁`
- `xianz -> 现在`
- `wsm -> 为什么`
- `sm -> 什么`
- `zmb -> 怎么办`
- `zhongguoren -> 中国人`
- `zhege api latnecy youdian gao -> 这个 API latency 有点高`

The bundled seed engine is intentionally small but should behave like a normal input method for the MVP cases it claims to support. Broader coverage enters through managed or user-owned local lexicons after license review; unknown pinyin-shaped gaps may use provider fallback only when the local engine has no candidate.

## Provider Layer

Every provider implements:

```text
func complete(_ request: LLMRequest) async throws -> LLMResponse
```

Provider-specific request and response shapes stay inside `KnowTypeProviders`. Core and input-method code only consume normalized `LLMResponse`.

Provider runtime loading uses:

- `ProviderProfile`: persisted metadata such as display name, kind, base URL, model, timeout, headers, custom HTTP mapping, and `secretName`.
- `ProviderProfileTemplates`: shared seeded defaults used by settings and runtime loading.
- `ProviderProfileResolver`: resolves `secretName` through `SecretStore`.
- `ProviderFactory`: builds the adapter for `openai_chat`, `openai_responses`, `anthropic_messages`, `gemini_native`, `ollama_native`, or `custom_http`.
- `ProviderConnectionDiagnostic`: settings-facing provider verification that sends a small prefix-locked continuation request and reports a normalized success or provider error.
- `KeychainSecretStore`: macOS storage for API keys under the `KnowType` service.

Profile JSON stores metadata and secret names only. It must not store API key values represented by `secretName`. Custom headers are persisted as configured, so the MVP docs warn users not to place bearer tokens directly in headers.

The seeded default provider is local OpenAI-compatible at `http://127.0.0.1:8317/v1`, with a blank model for `/v1/models` discovery and no embedded API key. Existing saved provider profiles override seeded defaults. Local OpenAI-compatible runtimes may leave the model blank for discovery. Remote OpenAI-compatible profiles require an explicit model ID.

## AI Layer

`KnowTypeAI` is the only layer that owns AI-specific input-method behavior:

- `AIRecommendationRuntime` builds real-time prefix-locked recommendation requests from raw input, the traditional first candidate, app context, `ENV.md`, and `CORRECTION.md`.
- `AIContextMemoryRuntime` records committed typing events and periodically summarizes them into the generated section of `~/.knowtype/ENV.md`.
- `EnvironmentDocumentStore` creates and updates `~/.knowtype/ENV.md`, preserving the user's notes outside the generated section.
- `CorrectionInstructionStore` creates `~/.knowtype/CORRECTION.md`; AI correction/recommendation prompts read instructions from this file, while the traditional engine remains deterministic.
- `AIHealthMonitor` counts provider timeouts, 429/5xx errors, and malformed responses. After repeated failures it enters cooldown so the input method can show an unavailable AI slot without sending more requests.

The input-method keydown path never awaits this layer. It publishes raw marked text and local candidates first, then receives AI slot updates asynchronously. Stale AI results are dropped by composition id and raw input before they can update the panel.

## Settings Layer

`KnowTypeSettingsUI` owns reusable user-facing configuration and status surfaces. `KnowTypeSettingsApp`, `KnowType.prefPane`, and the InputMethodKit preferences window host the same SwiftUI root view:

- `ProviderProfilesViewModel` edits provider profile metadata and coordinates API-key writes through `SecretStore`.
- Provider profile connection tests are transient and do not save profile metadata or draft API keys.
- `InputModePreferencesViewModel` edits punctuation language and symbol-width defaults stored in the shared `com.knowtype.preferences` defaults domain.
- `RuntimePreferencesViewModel` edits candidate paging/layout and AI continuation behavior through the same shared defaults domain. The legacy input-scheme value remains persisted for compatibility but is not exposed in the Rime-only settings UI.
- `LexiconSettingsViewModel` reports the local JSON/TSV lexicon directory status by reusing `KnowTypeCore` directory resolution and lexicon file loading.
- Lexicon settings can create missing directories, create a non-overwriting sample TSV file, install the recommended managed lexicon pack, and display installed pack metadata.

Settings status does not import the IMK frontend and does not own dictionary licensing. The macOS Keyboard/Input Sources page still only enables/selects the input method; KnowType-specific controls live in the PreferencePane or IMK preferences window.

## CLI And Local Tooling

KnowType includes small executable and shell-tooling targets for local
development, diagnostics, and lexicon management:

- `knowtype-demo` exercises the package-level correction, continuation, and
  commit flow without installing the input method.
- `knowtype-inputsource-tool` owns macOS Text Input Source status,
  TIS registration, legacy-mode disablement, and selection calls used by local
  scripts.
- `knowtype-lexicon-tool` installs managed local lexicon packs through
  `ManagedLexiconPackInstaller`.
- `scripts/build-inputmethod-bundle.sh` packages the local InputMethodKit app
  bundle into `dist/KnowType.app`.
- `scripts/install-inputmethod.sh`, `scripts/diagnose-inputmethod.sh`,
  `scripts/select-inputmethod.sh`, `scripts/repair-inputmethod-selection.sh`,
  and `scripts/uninstall-inputmethod.sh` form the local install and acceptance
  workflow.
- `scripts/smoke-inputmethod-install.sh` is the CI-safe script smoke path; it
  does not mutate Text Input Source state or prove target-app typing behavior.

Tooling is intentionally separate from product behavior. Scripts may prepare,
diagnose, or repair a local development installation, but manual acceptance in
real host apps remains the evidence for IMK behavior.

## Input Method Layer

`KnowTypeInputMethod` is the macOS front end:

- `KnowTypeInputController` is the thin IMK bridge for lifecycle, key events, marked text, commit, and palette visibility.
- `InputSessionController` remains available for core suggestion and commit policy, but the active IMK path uses Rime prefix snapshots for keydown responsiveness and delegates AI recommendation to `KnowTypeAI`.
- `CompositionBuffer` separates raw pinyin, resolved candidate segments, active raw range, marked-text display, and final commit text.
- `InputMethodLexiconRuntime` remains available for legacy demos/tests and settings visibility, but local lexicon rebuilds are not part of the IMK key path.
- Runtime preferences are loaded at controller startup and new composition boundaries; active marked text is not rewritten when settings change.
- Default runtime engine requests rebuild from current local lexicon directory contents instead of a process-wide static cache.
- The IMK controller publishes raw marked text and immediate Rime prefix candidates on the keydown path, then updates the fixed AI recommendation slot asynchronously.
- Runtime local lexicon snapshot checks and engine rebuilds are retired from the IMK coordinator; Rime artifacts and shared data are validated by bundle smoke tests.
- The IMK controller loads and saves recent prefix selections through a local user-selection history store, then passes snapshots into the suggestion context for local-only ranking.
- `CandidatePanelRenderer` maps suggestion state into compact macOS-style rows.
- `CandidatePanelWindowController` owns the AppKit panel, mouse interaction, and row accessibility.
- `CandidateAnchorResolver` resolves panel geometry from host text-system rectangles.
- `CandidatePanelLayoutEngine` measures rendered rows before AppKit layout, chooses horizontal versus vertical
  presentation, computes panel size and edge avoidance, and compresses vertical rows when a constrained visible
  frame cannot fit the natural height.

The IMK controller uses `IMKTextInput.setMarkedText` during active composition. Marked text shows raw pinyin until a Rime candidate is confirmed. Commit replaces the active marked range with raw input, the selected Rime prefix, or an explicitly selected AI recommendation depending on the shortcut.

User selection history is stored under Application Support as `user-selection-history.json`. This file is local candidate-learning data only; it is not serialized into provider requests.

## Candidate Window

KnowType uses a custom AppKit `NSPanel` as the primary candidate surface. It does not rely on `IMKCandidates` for active display because host-app behavior is inconsistent.

Candidate rows are flat and compact:

- Rime prefix candidate 1 appears first
- the AI recommendation slot appears second when AI state is pending, ready, disabled, or unavailable
- remaining Rime prefix candidates appear after the AI slot
- legacy continuation candidates may still be represented by core/session tests, but the production IMK panel uses the AI slot for provider-backed continuation
- raw input appears only when no suggestion is available
- adaptive layout pages up to 6 visible rows; vertical-list mode can show up to 9 visible rows

Candidate-window layout keeps those row semantics but derives horizontal versus vertical presentation from measured
row widths. Horizontal layout targets 4-6 complete candidates; vertical layout is used when long phrases would
otherwise leave only 1-3 complete horizontal candidates. The panel uses AppKit popover material, dynamic system
colors, compact 16 pt candidate text, 11 pt monospaced shortcut labels, a 0.5 pt separator border, continuous
corners, and system shadowing. The layout layer does not drop selectable rows after shortcuts are assigned; on
constrained visible frames it compresses vertical row height and spacing, and hides only when the frame cannot fit
the current page at the minimum row height.

Mouse hover selects enabled visible rows, click commits the same target as keyboard selection, and scroll-wheel
events page the panel. Pending, unavailable, or ineligible AI state rows are visible but disabled: they have muted
text, no numeric shortcut, no hover selection, and no click commit. Row accessibility elements expose button-like
labels for enabled candidates, static-text semantics for disabled AI status, and selected-children notifications
when the highlighted row changes. Candidate-panel screenshot baselines live under
`Tests/KnowTypeInputMethodTests/__Snapshots__/` and cover light horizontal, dark vertical, and AI-status examples.

Candidate positioning is centralized in `CandidateAnchorResolver`. The resolver tries fresh text geometry first, then progressively falls back:

1. marked and selected `firstRect` ranges
2. insertion-point range
3. line-height rectangles with bounded backtracking
4. Accessibility focused-range bounds when permission is already granted
5. same-composition last usable anchor scoped by composition, bundle, and screen
6. stable safe point inside the screen visible frame

Pointer location is not used as a moving candidate anchor.

## AI And Provider Timing

When a provider is configured, KnowType publishes raw marked text and local prefix candidates immediately. The second slot enters a pending AI state and is updated only when `AIRecommendationRuntime` returns a current result. If the provider fails, local correction still works and commit remains available, but KnowType does not show local mock continuation text as AI output.

No-provider paths remain traditional-input usable. Production runtimes can show `AI 未配置`, disabled, pending, ready, or unavailable state in the second slot. Level 0 paths do not call providers and do not log raw protected text.

## Privacy And App Rules

Level 0 protected input takes the no-provider path:

- URL, email, path, command-like, and code-like text commits unchanged by default.
- Terminal, iTerm, and Xcode contexts are protected by bundle identifier.
- Technical-token preservation does not automatically make an input Level 0; the surrounding text still determines provider eligibility.

Manual MVP acceptance must cover TextEdit, Safari, Chrome, Xcode, Terminal, WeChat, and Feishu because IMK behavior varies by host text system.
