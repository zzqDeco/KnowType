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
- `FileProviderProfileStore` persists profile JSON under Application Support when using the default store.
- `ProviderProfileResolver` resolves `secretName` through `SecretStore`.
- `KeychainSecretStore` is the macOS secret-store implementation.
- `ProviderFactory` maps `ProviderKind` to the concrete adapter.

Profile JSON must not store API key values represented by `secretName`. Custom headers are written to JSON as configured and should not contain secrets in the MVP.

Adapter tests should use mock HTTP clients and must not call real network services.
