# Sources/KnowTypeProviders

`KnowTypeProviders` maps external API protocols into the core `LLMProvider` interface.

Each adapter is responsible for:

- building a provider-native HTTP request
- setting authentication headers
- disabling streaming for v1 request/response simplicity
- extracting model text
- normalizing model text into `LLMResponse`

Adapter tests should use mock HTTP clients and must not call real network services.
