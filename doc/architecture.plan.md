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

Level 0 protected input remains a correction/local-protection concept: it avoids
rewriting URLs, paths, commands, code-like text, and protected app contexts.
Real-time AI recommendation uses a narrower secret-only hard block, so normal
technical text can still ask for AI continuation. The production IMK hot path no
longer uses the clean-room `TraditionalInputEngine` as a Chinese conversion
fallback; when Rime is unavailable, KnowType keeps raw input usable and reports
degraded conversion state instead of synthesizing hidden local candidates.

## Core Layer

`KnowTypeCore` owns model-neutral behavior:

- `TextProtection` detects Level 0 correction-protection input such as URLs,
  emails, paths, commands, code-like snippets, and protected app contexts, and
  separately detects secret-like credentials for cloud AI hard blocks.
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

- `AIRecommendationRuntime` builds real-time recommendation requests from raw input, optional user-confirmed `lockedPrefix`, app context, `ENV.md`, `CORRECTION.md`, and optional `LEXICAL_PROFILE.md`. Current-page Rime candidates are not sent to AI and do not become locked prefixes. Raw-input-only requests can trigger after three visible characters; confirmed locked prefixes keep the stricter two-Han-or-six-visible-character threshold.
- `AIContextMemoryRuntime` records committed typing events and periodically summarizes them into the generated section of `~/.knowtype/ENV.md`.
- `EnvironmentDocumentStore` creates and updates `~/.knowtype/ENV.md`, preserving the user's notes outside the generated section and repairing duplicate generated-section markers.
- `LexicalProfileStore` persists top-K lexical context from Rime userdb sync exports, recent commits, and selection history. The readable mirror is `~/.knowtype/LEXICAL_PROFILE.md`; the canonical JSON lives under Application Support.
- `CorrectionInstructionStore` creates `~/.knowtype/CORRECTION.md`; AI correction/recommendation prompts read instructions from this file, while the traditional engine remains deterministic.
- `AIHealthMonitor` counts provider timeouts, 429/5xx errors, and malformed responses. After repeated failures it enters cooldown so the input method can show an unavailable AI slot without sending more requests.
- `AIRecommendationDiagnosticSink` records privacy-preserving AI substates to macOS unified logging so provider latency, empty responses, prefix-lock filtering, stale drops, and cooldown can be diagnosed without logging raw input.
- Provider prompts are task-specific: real-time continuation uses suffix-only text when a locked prefix exists and full commit-ready text when only raw input and context are available, while correction, context digest, and polish keep separate instructions.

The input-method keydown path never awaits this layer. It publishes raw marked text and local candidates first, then receives AI slot updates asynchronously. AI results cross back into the IMK layer as `AIRecommendationPatch` values, which can update only the fixed AI slot after request id, generation, composition id, raw revision, and raw input all still match. They cannot change Rime selection, marked text, base candidates, or panel visibility. Rime userdb sync is a maintenance action and is not part of commit. Commit/selection profile refresh is delegated to `LexicalProfileRuntime` and reads only an already exported userdb snapshot; explicit `sync_user_data` is owned by `RimeMaintenanceService` for manual or idle maintenance paths. Keydown, Space, number selection, paging, and panel refresh do not read the userdb or touch disk for profile generation. Stale AI results are dropped by composition id and raw input before they can update the panel. The real-time recommendation runtime debounces for 350 ms by default and has a 10-second hard timeout; continuing to type still cancels older requests immediately.

## Settings Layer

`KnowTypeSettingsUI` owns reusable user-facing configuration and status surfaces. `KnowTypeSettingsApp`, `KnowType.prefPane`, and the InputMethodKit preferences window host the same SwiftUI root view. The primary UI is a macOS settings surface with a sidebar, search, and grouped-form detail pages for input, candidates, Rime/user data, AI continuation, privacy, and diagnostics. Localized settings strings use Simplified Chinese for Chinese preferred languages and English fallback resources for non-Chinese locales.

- `ProviderProfilesViewModel` edits provider profile metadata and coordinates API-key writes through `SecretStore`.
- Provider profile connection tests are transient and do not save profile metadata or draft API keys.
- `InputModePreferencesViewModel` edits punctuation language and symbol-width defaults stored in the shared `com.knowtype.preferences` defaults domain.
- `RuntimePreferencesViewModel` edits candidate paging/layout and AI continuation behavior through the same shared defaults domain. The legacy input-scheme value remains persisted for compatibility but is not exposed in the Rime-only settings UI.
- `LexiconSettingsViewModel` reports the local JSON/TSV lexicon directory status by reusing `KnowTypeCore` directory resolution and lexicon file loading.
- Lexicon settings can create missing directories, create a non-overwriting sample TSV file, install the recommended managed lexicon pack, and display installed pack metadata.
- Diagnostics settings read install-state, bundle metadata, Rime runtime presence, AI provider summary, user-data file timestamps, and backup availability. They display rollback commands but do not execute rollback from inside the running input-method/settings process.

Settings status does not import the IMK frontend and does not own dictionary licensing. The macOS Keyboard/Input Sources page still only enables/selects the input method; KnowType-specific controls live in the IMK preferences window, with the prefPane retained only as an optional compatibility host.

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
  `scripts/rollback-inputmethod.sh`, `scripts/select-inputmethod.sh`,
  `scripts/repair-inputmethod-selection.sh`, and
  `scripts/uninstall-inputmethod.sh` form the local install, rollback, and
  acceptance workflow.
- `scripts/smoke-inputmethod-install.sh` is the CI-safe script smoke path; it
  does not mutate Text Input Source state or prove target-app typing behavior.

Tooling is intentionally separate from product behavior. Scripts may prepare,
diagnose, or repair a local development installation, but manual acceptance in
real host apps remains the evidence for IMK behavior.
Install and rollback scripts swap only app/prefPane artifacts and preserve user
data in place. `install-state.json` and backup manifests provide traceability
for local upgrade testing without becoming product runtime dependencies.

## Input Method Layer

`KnowTypeInputMethod` is the macOS front end:

- `KnowTypeInputController` is the thin IMK bridge for lifecycle, key events, marked text, commit, and palette visibility.
- `InputSessionController` remains available for core suggestion and commit policy, but the active IMK path uses Rime prefix snapshots for keydown responsiveness and delegates AI recommendation to `KnowTypeAI`.
- `CompositionBuffer` remains available for legacy/session tests, but native Rime preedit is the production marked-text source during active Chinese composition.
- `InputMethodLexiconRuntime` remains available for legacy demos/tests and settings visibility, but local lexicon rebuilds are not part of the IMK key path.
- Runtime preferences are loaded at controller startup and new composition boundaries; active marked text is not rewritten when settings change.
- Default runtime engine requests rebuild from current local lexicon directory contents instead of a process-wide static cache.
- The IMK controller publishes Rime preedit marked text and immediate current-page Rime prefix candidates on the keydown path, then updates the fixed AI recommendation slot asynchronously.
- Runtime local lexicon snapshot checks and engine rebuilds are retired from the IMK coordinator; Rime artifacts and shared data are validated by bundle smoke tests.
- The IMK controller loads and saves recent prefix selections through a local user-selection history store, then passes snapshots into the suggestion context for local-only ranking.
- The input-method menu follows mature IMK inputs such as McBopomofo: common toggles appear first, user data and diagnostic folders are in the middle, and `KnowType Settings...` calls `showPreferences(_:)` to open the in-bundle settings window.
- `CandidatePanelRenderer` maps suggestion state into compact macOS-style rows.
- `CandidatePanelPresenter` is the coordinator-side presentation boundary. It consumes `CandidatePanelFrame` values with composition id, raw revision, anchor source, panel model, and explicit visibility reason before touching the host's AppKit panel adapter.
- `CandidatePanelWindowController` owns the AppKit panel, mouse interaction, and row accessibility.
- `CandidateAnchorResolver` resolves panel geometry from host text-system rectangles.
- `CandidatePanelLayoutEngine` measures rendered rows before AppKit layout, chooses horizontal versus vertical
  presentation, computes panel size and edge avoidance, and compresses vertical rows when a constrained visible
  frame cannot fit the natural height.

The IMK controller uses `IMKTextInput.setMarkedText` during active composition. Marked text mirrors Rime preedit, including partial-commit states where confirmed Chinese text and remaining raw input coexist. Commit replaces the active marked range with raw input, the highlighted Rime candidate, or an explicitly selected AI recommendation depending on the shortcut.

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
events page the panel. Arrow keys update Rime's highlighted candidate: right/down at the page end moves to the
next page's first row, while left/up at the page start moves to the previous page's last row. Explicit
`PageUp`/`PageDown` keep working while composition is active even if the panel is hidden.
Rime-compatible paging punctuation (`-`/`=`, `,`/`.`) also drives the native Rime page state before punctuation
commit fallback. Pending, unavailable, or ineligible AI state rows are visible but disabled; ready AI rows use Tab
as their visible shortcut and do not take ordinary number keys from Rime candidates. Row accessibility elements expose button-like
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

No-provider paths remain traditional-input usable. Production runtimes can show
`AI 未配置`, disabled, pending, ready, or unavailable state in the second slot.
Disabled real-time AI maps to secret-like raw input or locked prefixes; ordinary
technical text, paths, URLs, commands, and protected app contexts do not directly
produce `AI 已禁用`.

## Privacy And App Rules

Level 0 correction protection keeps these inputs from being rewritten by local
or cloud correction:

- URL, email, path, command-like, and code-like text commits unchanged by default.
- Terminal, iTerm, and Xcode contexts remain correction-protected by bundle
  identifier.
- Technical-token preservation does not automatically make an input Level 0;
  secret-like content determines the real-time AI hard block.

Cloud AI recommendation uses secret-only hard blocking. Candidate hints that
look like credentials are filtered before the request; safe hints remain usable.

Manual MVP acceptance must cover TextEdit, Safari, Chrome, Xcode, Terminal, WeChat, and Feishu because IMK behavior varies by host text system.
