# KnowType

KnowType is a macOS Chinese/English AI input method. It corrects and understands the prefix the user is typing first, then generates natural continuation candidates without rewriting the locked prefix.

Chinese name: 知键.

## Product Rule

KnowType must preserve confirmed user text by default:

```text
raw input -> correction -> locked prefix -> continuation
```

AI continuation candidates are only the text after the locked prefix. Rewriting the prefix is allowed only when the user explicitly triggers polish.

## Protocol Support

The provider layer is protocol-oriented and does not bind KnowType to one vendor.

- `openai_chat`: `/v1/chat/completions`
- `openai_responses`: `/v1/responses`
- `anthropic_messages`: `/v1/messages`
- `gemini_native`: `models.generateContent`
- `ollama_native`: `/api/chat`
- `custom_http`: templated request body plus response path extraction

All adapters normalize responses into:

```text
LLMResponse {
  candidates: [
    { text, confidence?, reason? }
  ]
}
```

## Repository Layout

```text
Sources/KnowTypeCore/          Core models, correction, prefix-locked continuation
Sources/KnowTypeProviders/     Provider adapters and HTTP normalization
Sources/KnowTypeInputMethod/   Input-method interaction contracts and IMK bootstrap
Tests/                         Unit and adapter tests
plan/                          Current implementation plans
doc/                           Architecture and interface documentation
Resources/                     Dictionaries, schema notes, and future bundled assets
```

## Development

```bash
swift build
swift test
```

Provider profiles are persisted as JSON without API keys. Secrets are resolved through `SecretStore`; the macOS implementation uses Keychain.

Try the package-level MVP flow without installing an input method:

```bash
swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan
swift run knowtype-demo --locale mixed --action tab zhege api latnecy youdian gao
swift run knowtype-demo --locale en-US --action tab I thikn this approch
```

## Interaction Contract

- `Space`: commit the best prefix candidate.
- `Tab`: commit the best prefix plus the first continuation.
- `Option + number`: commit the best prefix plus the selected continuation.
- `Option + R`: request polish; this is the only default path that may rewrite the prefix.

## Privacy Baseline

Level 0 contexts such as URLs, emails, file paths, code snippets, and terminal input are not sent to a cloud provider. API keys must be stored in Keychain when the macOS app layer is added.
