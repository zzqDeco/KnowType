# PromptBuilder

## Responsibility

`PromptBuilder` turns `LLMRequest` into task-specific prompt text for provider
adapters.

## Boundaries

- It owns task-specific provider-facing instructions, not adapter-specific HTTP
  payloads.
- Product invariants still live in core sanitizers and tests; prompts are not a
  trusted enforcement layer.

## Behavior Notes

- Continuation prompts distinguish confirmed `lockedPrefix` from unconfirmed raw
  input. With a locked prefix, candidate text must be directly appendable after
  it and must not repeat or paraphrase it. Without a locked prefix, raw input
  may be pinyin, English, or a technical token; candidate text is a full
  commit-ready recommendation from raw input and context.
  The prompt asks for language and intent aligned with the request context; it
  must not force Chinese output for English or mixed-locale input.
- Correction and polish prompts must keep the distinction between prefix
  refinement and explicit rewrite.
- Context digest prompts use the separate `{ "markdown": "..." }` shape and
  must not receive continuation-oriented suffix examples.
- Providers may ignore prompts, so response sanitization remains required.

## Tests

- `ProviderAdapterTests`
- `PrefixContinuationEngineTests`
