# ProviderProfileTemplates

## Responsibility

`ProviderProfileTemplates` owns seeded provider defaults shared by settings and
the input-method runtime.

## Boundaries

- Seeded templates are defaults, not saved user configuration.
- They must not embed API keys.

## Behavior Notes

- The default seeded profile is local OpenAI-compatible at
  `http://127.0.0.1:8317/v1`.
- The model may remain blank for local `/v1/models` discovery.
- Settings and runtime loading should use the same seeded defaults so a fresh
  install behaves consistently.
- New Anthropic and Gemini templates use `claude-haiku-4-5-20251001` and
  `gemini-3.5-flash`.
- Exact retired template IDs migrate through an expected-revision transaction
  only for the matching provider kind and official HTTPS endpoint. Anthropic
  accepts root and `/v1` base paths; Gemini remains root-only. Proxy hosts,
  custom paths, queries, userinfo, fragments, nonstandard ports, and non-exact
  IDs are never rewritten.
- A revision conflict reloads current profiles once before retrying so unrelated
  concurrent edits are preserved.

## Tests

- `ProviderProfileTests`
- `ProviderProfilesViewModelTests`
