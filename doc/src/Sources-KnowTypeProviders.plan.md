# Sources/KnowTypeProviders

`KnowTypeProviders` maps external API protocols into the core `LLMProvider` interface.

Each adapter is responsible for:

- building a provider-native HTTP request
- setting authentication headers
- disabling streaming for v1 request/response simplicity
- extracting model text
- normalizing model text into `LLMResponse`

Runtime provider loading is profile-based:

- `ProviderProfile` stores provider metadata and `secretName`.
- `ProviderProfileTemplates` owns seeded provider profiles shared by the settings app and the input-method runtime.
- `FileProviderProfileStore` persists profile JSON under Application Support when using the default store.
- `ProviderProfileResolver` resolves `secretName` through `SecretStore`.
- `KeychainSecretStore` is the macOS secret-store implementation.
- `ProviderFactory` maps `ProviderKind` to the concrete adapter.
- `ProviderConnectionDiagnostic` builds a provider and sends a small prefix-locked continuation request to verify the configured endpoint.
- `ProviderConfiguration.endpoint(path:)` normalizes OpenAI-compatible `/v1` base URLs with or without a trailing slash before appending adapter paths.
- `OpenAICompatibleModelDiscovery` may resolve blank or placeholder model IDs only for local OpenAI-compatible runtimes.

Profile JSON must not store API key values represented by `secretName`. Custom headers are written to JSON as configured and should not contain secrets in the MVP.

When `providers.json` is empty or missing, runtime loading uses the same seeded templates as settings. The seeded default is a local OpenAI-compatible profile at `http://127.0.0.1:8317/v1` with a blank model for `/v1/models` discovery and no embedded API key.

Provider errors conform to `LocalizedError` so settings diagnostics can show the same readable messages used in tests and logs.

Adapter tests should use mock HTTP clients and must not call real network services.
