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

- Continuation prompts use a suffix-generator contract: candidate text must be
  directly appendable after `lockedPrefix`, must not repeat or paraphrase the
  locked prefix, and should return an empty array only for unsafe, impossible, or
  nonsensical prefixes.
- Correction and polish prompts must keep the distinction between prefix
  refinement and explicit rewrite.
- Context digest prompts use the separate `{ "markdown": "..." }` shape and
  must not receive continuation-oriented suffix examples.
- Providers may ignore prompts, so response sanitization remains required.

## Tests

- `ProviderAdapterTests`
- `PrefixContinuationEngineTests`
