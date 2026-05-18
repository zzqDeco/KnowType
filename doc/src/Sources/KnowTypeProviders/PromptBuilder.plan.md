# PromptBuilder

## Responsibility

`PromptBuilder` turns `LLMRequest` into task-specific prompt text for provider
adapters.

## Boundaries

- It owns shared provider-facing instructions, not adapter-specific HTTP
  payloads.
- Product invariants still live in core sanitizers and tests; prompts are not a
  trusted enforcement layer.

## Behavior Notes

- Continuation prompts must ask for continuation text only.
- Correction and polish prompts must keep the distinction between prefix
  refinement and explicit rewrite.
- Providers may ignore prompts, so response sanitization remains required.

## Tests

- `ProviderAdapterTests`
- `PrefixContinuationEngineTests`
