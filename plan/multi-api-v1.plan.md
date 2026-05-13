# KnowType Multi-API v1 Plan

## Goal

Implement the first usable KnowType core around multi-protocol provider compatibility, correction-first processing, and prefix-locked continuation.

## Scope

- Swift Package foundation with `KnowTypeCore`, `KnowTypeProviders`, and `KnowTypeInputMethod`.
- Local Level 0/1 correction rules and examples for Chinese pinyin, English, and mixed input.
- Provider adapters for OpenAI Chat Completions, OpenAI Responses, Anthropic Messages, Gemini native, Ollama native, and custom HTTP.
- Settings-app provider profiles with JSON metadata persistence, profile-scoped secrets, remote OpenAI model validation, and local/no-secret provider cleanup.
- Input action contract for Space, Tab, Option-number, and Option-R.
- Unit tests for product invariants and adapter mapping.

## Non-Goals

- Full Xcode app bundle and signed InputMethodKit installation package.
- Complete pinyin or shuangpin decoder.
- Vendor-specific account UI.
- App Store release hardening.

## Verification

```bash
swift build
swift test
```

Manual macOS IMK verification is required once the app bundle target is added.
