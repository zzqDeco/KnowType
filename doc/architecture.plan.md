# KnowType Architecture

## Pipeline

```text
raw input
  -> TextProtection
  -> CorrectionEngine
  -> LockedPrefix
  -> PrefixContinuationEngine
  -> InputCompositionController
  -> commit text
```

## Core Boundaries

- `KnowTypeCore` owns product rules and model-neutral behavior.
- `KnowTypeProviders` owns protocol-specific HTTP mapping and response parsing.
- `KnowTypeInputMethod` owns macOS input actions and future InputMethodKit integration.

## Correction Engine

Local correction always runs before cloud correction. Level 0 inputs return immediately and must not call cloud providers.

Level 0 contexts include URLs, emails, file paths, command-like input, code-like tokens, and protected app bundle IDs for Terminal, iTerm2, and Xcode.

Current local coverage:

- pinyin typo examples such as `fagnan -> fangan -> 方案`
- English typo examples such as `thikn -> think`
- mixed technical input such as `zhege api latnecy youdian gao`
- technical token canonicalization for `API`, `JSON`, `FastAPI`, `iOS`, `macOS`, and `InputMethodKit`

Cloud correction may add Level 2/3 alternatives, but strong correction is treated as an alternative, not an automatic replacement.

## Continuation Engine

Continuation requests include `locked_prefix`. Provider output is sanitized locally:

- if output repeats the locked prefix, strip the prefix and keep only the continuation
- if the remaining continuation is empty, reject it
- fallback local continuations are available when the provider fails

Level 0 contexts return no continuation candidates.

## Provider Architecture

Every provider implements `LLMProvider`:

```text
func complete(_ request: LLMRequest) async throws -> LLMResponse
```

Adapters must not leak native response shapes into the core. All provider responses normalize into `LLMResponse`.

Provider runtime loading uses `ProviderProfile` plus `ProviderFactory`:

- `ProviderProfile` stores display name, provider kind, base URL, model, timeout, headers, custom HTTP mapping fields, and `secretName`.
- `ProviderProfileResolver` resolves `secretName` through `SecretStore` and returns `ProviderConfiguration`.
- `ProviderFactory` selects the adapter for `openai_chat`, `openai_responses`, `anthropic_messages`, `gemini_native`, `ollama_native`, or `custom_http`.
- Profile JSON must not contain API key values represented by `secretName`. Custom headers are stored in JSON as configured and should not contain secrets in the MVP. The macOS secret-store implementation uses Keychain.

Provider profiles are edited by the settings app and stored as JSON metadata plus profile-scoped `SecretStore` entries. API keys are never written to the profile file. Cloud profiles require either a newly entered key or an existing reusable secret. Custom HTTP profiles accept a blank API key for unauthenticated endpoints, while still storing an optional profile-scoped secret when a key is entered. When a profile switches to a local/no-secret provider such as Ollama, the settings model clears the draft key and deletes the old secret only if no remaining saved profile references it. Profile saves publish the updated profile list only after both the metadata save and required secret mutation succeed; if a post-save secret mutation fails, the metadata file is restored to the previous state.

## Input Method Layer

The current package includes:

- `InputCompositionController` for shortcut behavior
- `CandidatePanelViewModel` for separated prefix and continuation data
- `CandidatePanelRenderer` for raw input, locked prefix, and continuation render rows
- `KnowTypeIMKServerBootstrap` behind `canImport(InputMethodKit)` for IMK server integration
- `KnowTypeInputController` as the InputMethodKit session controller
- `KnowTypeInputMethodApp` as the background app entry point assembled by `scripts/build-inputmethod-bundle.sh`

The IMK controller uses `IMKTextInput.setMarkedText` for active composition so local pinyin can become marked Chinese text before commit. Commit calls replace the active marked range with either the locked prefix or the prefix plus selected continuation.

The primary candidate surface is a controlled AppKit `NSPanel` styled as a compact macOS candidate list. We do not rely on `IMKCandidates` for active display because it can silently fail to appear in some host apps. Candidate data includes prefix candidates first and continuation candidates after them; raw input is shown only when no suggestion is available.

Candidate positioning recalculates after local and async suggestion publication. Anchor lookup prefers the marked range end, falls back to selected range, then falls back to the client line-height rectangle before using pointer location as the screen fallback.

When a provider is configured, the immediate local pass publishes correction/prefix rows only. Continuation rows are published after the provider-backed suggestion returns; local fallback continuations are reserved for no-provider and provider-failure paths.

## Privacy and App Rules

Level 0 protected input takes the no-provider path:

- URL, email, path, command-like, and code-like text is committed unchanged by default.
- Terminal, iTerm, and Xcode contexts are Level 0 by app bundle identifier.
- Level 0 responses clear continuation candidates so cloud continuation is not offered.
- Technical tokens such as `API`, `JSON`, `FastAPI`, `iOS`, `macOS`, and `InputMethodKit` are preserved or canonicalized, but they are not by themselves a no-cloud Level 0 trigger.

Manual MVP acceptance must cover TextEdit, Safari, Chrome, Xcode, Terminal, WeChat, and Feishu because IMK behavior depends on host-app text systems.

## Release Readiness

MVP release docs should be finalized after the runtime provider branch is integrated on `dev`. Rebase the docs branch on that combined state, keep documentation-only commits separate from runtime code, and validate with `swift build`, `swift test`, candidate panel manual checks, provider profile/Keychain checks, Level 0 no-cloud checks, and `git diff --check`.
