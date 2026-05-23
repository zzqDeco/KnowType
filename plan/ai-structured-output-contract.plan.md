# KnowType AI Structured Output Contract

## Status

Active

## Summary

- Branch: `fix/ai-structured-output-contract`; PR base: `dev`.
- Replace prompt-only JSON mode with provider-level structured output when supported.
- Keep prefix-lock validation local so schema correctness cannot rewrite the locked prefix.
- Make `AI 无推荐` diagnosable through structured-output, sanitizer, and prefix-length reasons.

## Implementation

- `KnowTypeProviders` owns a shared JSON Schema contract for candidate responses and context digest responses.
- OpenAI Chat and Responses prefer `json_schema` with `strict=true`; unsupported OpenAI-compatible runtimes fall back once to JSON mode and cache that capability result.
- Gemini and Anthropic send provider-native schema hints and fall back to prompt-only JSON when the endpoint rejects the schema fields.
- Ollama and custom HTTP do not claim provider-enforced schema; they still use strict local decoding.
- `AIRecommendationRuntime` rejects too-short prefixes before cloud calls and records structured-output fallback, decode failure, sanitizer repair, and sanitizer reject reasons without logging raw text.
- Review hardening scopes schema fallback cache by auth/header fingerprint and only treats schema-specific 400/422 failures as capability downgrades.
- OpenAI Responses has two fallback forms: `json_object` when only `json_schema` is rejected, and prompt-only strict local decoding when an OpenAI-compatible runtime rejects the `text` field itself.

## Validation

- Unit tests cover strict schema request bodies, fallback retry, strict decoding, sanitizer reasons, AI diagnostics, and provider connection diagnostics.
- Required checks: `swift test --quiet`, `./scripts/smoke-inputmethod-install.sh`, `./scripts/perf-input-hotpath.sh`, `git diff --check`.

## Assumptions

- This work does not change Rime hot paths, candidate UI, model selection UI, `main`, or release packaging.
- Structured output constrains shape only; `PrefixContinuationEngine` remains the authoritative guard for locked-prefix safety.
