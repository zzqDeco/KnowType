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

## Provider Architecture

Every provider implements `LLMProvider`:

```text
func complete(_ request: LLMRequest) async throws -> LLMResponse
```

Adapters must not leak native response shapes into the core. All provider responses normalize into `LLMResponse`.

## Input Method Layer

The current package includes:

- `InputCompositionController` for shortcut behavior
- `CandidatePanelViewModel` for separated prefix and continuation sections
- `KnowTypeIMKServerBootstrap` behind `canImport(InputMethodKit)` for future app-bundle integration
- `KnowTypeInputController` as the InputMethodKit session controller
- `KnowTypeInputMethodApp` as the background app entry point assembled by `scripts/build-inputmethod-bundle.sh`
