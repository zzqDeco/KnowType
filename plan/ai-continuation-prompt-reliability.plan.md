# KnowType AI Continuation Prompt Reliability

## Status

Active

## Summary

- Branch: `fix/ai-continuation-prompt-reliability`; PR base: `dev`.
- Make continuation prompts task-specific so `gpt-5.3-codex-spark` treats KnowType as a suffix generator instead of conservatively returning empty candidates for valid prefixes.
- Repair duplicated generated-section markers in `~/.knowtype/ENV.md` without changing provider profiles, model selection, Rime, or candidate-panel behavior.

## Implementation

- `PromptBuilder` exposes `systemPrompt(for:)` and keeps separate prompts for continuation, correction, context digest, and polish.
- The continuation prompt is short and explicit: provider output must be JSON, candidate `text` is suffix-only, `lockedPrefix` must not be repeated or rewritten, and empty candidates are reserved for unsafe, impossible, or nonsensical prefixes.
- Provider adapters pass the task-specific prompt into OpenAI Chat, OpenAI Responses, Anthropic Messages, Gemini native, and Ollama native request bodies while preserving strict schema and fallback behavior.
- `EnvironmentDocumentStore` repairs duplicate generated marker blocks on load and before generated-section replacement, preserving user notes while collapsing generated content to one guarded section.

## Test Plan

- Unit tests cover continuation-specific prompt content, non-continuation prompt separation, provider request-body prompt mapping, strict output behavior, and `ENV.md` marker repair.
- Required checks: `swift test --quiet`, `./scripts/smoke-inputmethod-install.sh`, `./scripts/perf-input-hotpath.sh`, `git diff --check`.
- Local live smoke uses the current local OpenAI-compatible profile and `gpt-5.3-codex-spark`; `lockedPrefix="我觉得这个方案"` should return at least one sanitizer-accepted continuation within the existing 10-second AI runtime limit.

## Assumptions

- Empty candidates remain valid only for unsafe, impossible, or nonsensical prefixes.
- Prefix-lock sanitizer remains the authoritative guard; prompts improve reliability but are not trusted enforcement.
- This slice does not touch `main` or release packaging.
