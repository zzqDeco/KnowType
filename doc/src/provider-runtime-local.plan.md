# Local OpenAI-Compatible Provider Runtime

KnowType supports OpenAI-compatible local endpoints without hardcoding a model id in profile JSON.

Runtime behavior:

- If `providers.json` is empty or missing, `ProviderRuntimeLoader` seeds the same default local OpenAI-compatible profile shown by settings.
- `OpenAIChatProvider` and `OpenAIResponsesProvider` resolve blank or placeholder model values through `GET /v1/models`.
- Discovery uses only the generic OpenAI-compatible response shape: a top-level `data` array with model `id` strings.
- Discovery honors configured base URLs that already include `/v1`, custom headers, timeouts, and optional bearer tokens.
- API key values are not stored in provider profiles; profiles only carry optional `secretName` references.
- Discovery failures throw from the provider request path. Core correction and continuation engines already treat provider failures as optional and continue with local or fallback behavior.

Placeholder model values currently resolved through discovery:

- empty or whitespace-only strings
- `<model>`
- `<model-id>`
- `{{model}}`
- `{{model_id}}`
- `placeholder`
- `replace-me`
- `replace_me`
- `your-model-id`
- `your_model_id`
- `todo`
