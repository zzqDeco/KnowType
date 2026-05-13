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
Sources/KnowTypeSettingsApp/   SwiftUI settings and provider profile editing
Tests/                         Unit and adapter tests
plan/                          Current implementation plans
doc/                           Architecture and interface documentation
Resources/                     Dictionaries, schema notes, and future bundled assets
```

## Development

```bash
swift build
swift test
./scripts/build-inputmethod-bundle.sh
```

Provider profiles are persisted as JSON without API keys. Secrets are resolved through `SecretStore`; the macOS implementation uses Keychain. The settings app edits provider profiles for OpenAI, Anthropic, Gemini, Ollama, and custom HTTP endpoints. Cloud profiles require a new key or an existing Keychain secret. Custom HTTP profiles may omit the API key for local proxy endpoints, or store an optional profile-scoped key when one is entered. Switching a profile to a local/no-secret provider clears the draft API key and deletes the old profile-scoped secret only when no other saved profile still references it.

To install the local macOS input method bundle:

```bash
./scripts/install-inputmethod.sh
```

Then enable KnowType in System Settings > Keyboard > Text Input > Input Sources. Use `./scripts/uninstall-inputmethod.sh` to remove the local bundle.

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
