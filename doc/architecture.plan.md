# KnowType Architecture

KnowType is split into three layers:

- `KnowTypeCore`: product rules, correction, protected-input detection, prefix locking, and continuation sanitization.
- `KnowTypeProviders`: provider profile resolution, HTTP adapters, model discovery, and response normalization.
- `KnowTypeInputMethod`: macOS input-method integration, marked text, key behavior, candidate state, and candidate-window presentation.

The product boundary is strict: correction may refine the prefix, but continuation may only append text after the locked prefix. Explicit polish is the only rewrite path.

## Input Pipeline

```text
raw input
  -> TextProtection
  -> CorrectionEngine
  -> LockedPrefix
  -> PrefixContinuationEngine
  -> InputSessionController
  -> IMK marked text / commit
```

Level 0 protected input exits through the no-provider path. It must not call cloud providers and must not publish cloud continuation candidates.

## Core Layer

`KnowTypeCore` owns model-neutral behavior:

- `TextProtection` detects Level 0 input such as URLs, emails, paths, commands, code-like snippets, and protected app contexts.
- `TraditionalInputEngine` provides clean-room MVP pinyin decoding with compact segmentation, indexed lexicon lookup, typo normalization, same-pinyin candidates, partial-syllable handling, and initial abbreviations.
- `TraditionalInputEngine` can also be initialized with authorized local lexicon entries. Those entries use the same private index as the seed lexicon, so larger dictionaries, future bundled resources, and local user lexicons do not need a separate parser path.
- `CorrectionEngine` can boost generated prefix candidates from local user selection history without adding new dictionary entries or sending selection data to providers.
- English and mixed-input paths preserve technical tokens such as `API`, `JSON`, `FastAPI`, `iOS`, `macOS`, and `InputMethodKit`.
- `CorrectionEngine` may ask a configured provider for unknown pinyin-shaped input only when `TraditionalInputEngine` reports no local candidate and the input is not protected technical or English text.
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

The local engine is intentionally small but should behave like a normal input method for the MVP cases it claims to support. Broader dictionaries should enter through the local lexicon-extension path after license review; unknown pinyin-shaped gaps may use provider fallback only when the local engine has no candidate.

## Provider Layer

Every provider implements:

```text
func complete(_ request: LLMRequest) async throws -> LLMResponse
```

Provider-specific request and response shapes stay inside `KnowTypeProviders`. Core and input-method code only consume normalized `LLMResponse`.

Provider runtime loading uses:

- `ProviderProfile`: persisted metadata such as display name, kind, base URL, model, timeout, headers, custom HTTP mapping, and `secretName`.
- `ProviderProfileResolver`: resolves `secretName` through `SecretStore`.
- `ProviderFactory`: builds the adapter for `openai_chat`, `openai_responses`, `anthropic_messages`, `gemini_native`, `ollama_native`, or `custom_http`.
- `KeychainSecretStore`: macOS storage for API keys under the `KnowType` service.

Profile JSON stores metadata and secret names only. It must not store API key values represented by `secretName`. Custom headers are persisted as configured, so the MVP docs warn users not to place bearer tokens directly in headers.

Local OpenAI-compatible runtimes may leave the model blank for `/v1/models` discovery. Remote OpenAI-compatible profiles require an explicit model ID.

## Input Method Layer

`KnowTypeInputMethod` is the macOS front end:

- `KnowTypeInputController` is the thin IMK bridge for lifecycle, key events, marked text, commit, and palette visibility.
- `InputSessionController` turns raw input and actions into suggestion and commit decisions.
- The IMK controller loads and saves recent prefix selections through a local user-selection history store, then passes snapshots into the suggestion context for local-only ranking.
- `CandidatePanelRenderer` maps suggestion state into compact macOS-style rows.
- `CandidatePanelWindowController` owns the AppKit panel.
- `CandidateAnchorResolver` resolves panel geometry from host text-system rectangles.

The IMK controller uses `IMKTextInput.setMarkedText` during active composition. Commit replaces the active marked range with either the selected prefix or prefix plus continuation.

User selection history is stored under Application Support as `user-selection-history.json`. This file is local candidate-learning data only; it is not serialized into provider requests.

## Candidate Window

KnowType uses a custom AppKit `NSPanel` as the primary candidate surface. It does not rely on `IMKCandidates` for active display because host-app behavior is inconsistent.

Candidate rows are flat and compact:

- prefix candidates appear first
- continuation candidates appear after prefix candidates
- raw input appears only when no suggestion is available
- rows are paged in 9-row windows

Candidate positioning is centralized in `CandidateAnchorResolver`. The resolver tries fresh text geometry first, then progressively falls back:

1. marked and selected `firstRect` ranges
2. insertion-point range
3. line-height rectangles with bounded backtracking
4. Accessibility focused-range bounds when permission is already granted
5. same-composition last usable anchor scoped by composition, bundle, and screen

Pointer location is not used as a moving candidate anchor.

## Provider Timing

When a provider is configured, KnowType publishes local prefix candidates immediately. Continuation rows are published after the provider-backed suggestion returns. If the provider fails, local correction still works and commit remains available.

No-provider and provider-failure paths may use local fallback continuations. Level 0 paths clear continuation candidates.

## Privacy And App Rules

Level 0 protected input takes the no-provider path:

- URL, email, path, command-like, and code-like text commits unchanged by default.
- Terminal, iTerm, and Xcode contexts are protected by bundle identifier.
- Technical-token preservation does not automatically make an input Level 0; the surrounding text still determines provider eligibility.

Manual MVP acceptance must cover TextEdit, Safari, Chrome, Xcode, Terminal, WeChat, and Feishu because IMK behavior varies by host text system.
