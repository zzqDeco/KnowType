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
Sources/KnowTypeProviders/     Provider profiles, runtime loading, adapters, HTTP normalization
Sources/KnowTypeInputMethod/   Input-method interaction, native candidates, IMK bootstrap
Sources/KnowTypeInputMethodApp Local macOS IMK background app entry point
Sources/KnowTypeSettingsApp/   SwiftUI settings and provider profile editing
Tests/                         Unit and adapter tests
plan/                          Current implementation plans
doc/                           Architecture and interface documentation
Resources/                     Dictionaries, schema notes, and future bundled assets
```

## Build and Install

Requirements:

- macOS 13 or newer for the local InputMethodKit bundle.
- Swift 6.2 toolchain.

Package checks:

```bash
swift build
swift test
```

Build the local input method app bundle:

```bash
./scripts/build-inputmethod-bundle.sh
```

The bundle is written to `dist/KnowType.app`.

To install the local macOS input method bundle:

```bash
./scripts/install-inputmethod.sh
```

The script copies the bundle to `~/Library/Input Methods/KnowType.app`. Then enable KnowType in System Settings > Keyboard > Text Input > Input Sources. If the input source list does not refresh, log out and back in, or restart the affected app.

During local input, KnowType uses the native macOS candidate panel where possible. It marks the composing text in the client app first, then `Space` replaces that marked text with the best corrected prefix, while `Tab` replaces it with prefix plus the first continuation.

To remove the local bundle:

```bash
./scripts/uninstall-inputmethod.sh
```

This is MVP local packaging. It is not a signed installer, notarized release, or App Store package.

## Demo Flow

Try the package-level MVP flow without installing an input method:

```bash
swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan
swift run knowtype-demo --locale mixed --action tab zhege api latnecy youdian gao
swift run knowtype-demo --locale en-US --action tab I thikn this approch
```

## Provider Configuration

KnowType loads providers through `ProviderProfile` plus `ProviderFactory`. Profiles are stored as JSON without API keys. The default file store writes to:

```text
~/Library/Application Support/KnowType/providers.json
```

Profile fields include:

```text
id, displayName, kind, baseURL, model, timeoutSeconds, headers,
secretName, customBodyTemplate, customResponsePath, isDefault
```

`secretName` is resolved through `SecretStore`. On macOS, `KeychainSecretStore` stores API keys in Keychain under the `KnowType` service; provider profile JSON stores the `secretName`, not the API key value. Custom `headers` are persisted in provider JSON as configured, so do not put bearer tokens or other secrets in headers for the MVP. Tests and non-UI flows can use in-memory or dictionary-backed secret stores.

The settings app edits provider profiles for OpenAI, Anthropic, Gemini, Ollama, and custom HTTP endpoints. Cloud profiles require a new key or an existing Keychain secret. Custom HTTP profiles may omit the API key for local proxy endpoints, or store an optional profile-scoped key when one is entered. Switching a profile to a local/no-secret provider clears the draft API key and deletes the old profile-scoped secret only when no other saved profile still references it.

The provider runtime supports:

- `openai_chat`: `/v1/chat/completions`
- `openai_responses`: `/v1/responses`
- `anthropic_messages`: `/v1/messages`
- `gemini_native`: `models.generateContent`
- `ollama_native`: `/api/chat`
- `custom_http`: templated request body plus response path extraction

All provider responses must normalize into `LLMResponse` before reaching core or input-method code.

## Interaction Contract

- `Space`: commit the selected prefix candidate only.
- `Tab`: commit the selected prefix plus the first or selected continuation.
- `Option + number`: commit the selected prefix plus the continuation shown with that shortcut. `Option + 1` matches the first continuation and is also shown as `Tab / Option+1`.
- `Option + R`: request polish; this is the only default path that may rewrite the prefix.

The native candidate list shows prefix candidates first and continuation candidates after them. Local fallback now provides up to six medium continuation candidates when the provider is unavailable.

## Privacy Baseline

Level 0 contexts such as URLs, emails, file paths, command-like input, code-like snippets, Terminal/iTerm input, and Xcode input are protected. They use the no-provider path, produce no cloud continuation candidates, and commit unchanged by default.

Known protected examples:

- URLs and `www.` addresses.
- Email-like input.
- Absolute, home-relative, and relative file paths.
- Code-like input containing braces, semicolons, or `=>`.
- Command-like input such as `swift test` or `git status`.
- Terminal, iTerm, and Xcode sessions by bundle identifier.

Technical tokens such as `API`, `JSON`, `FastAPI`, `iOS`, `macOS`, `InputMethodKit`, `snake_case`, and `camelCase` are preservation rules. Mixed prose containing those tokens may still use the configured provider unless it also matches a Level 0 rule above.

## MVP Manual Acceptance

Before tagging an MVP build, run `swift build`, `swift test`, build/install the local input method bundle, and manually verify:

- TextEdit: candidate window appears; `Space` commits prefix only.
- Safari and Chrome: text fields accept `Tab` for prefix plus first continuation.
- Xcode: technical tokens and code-like identifiers are preserved.
- Terminal: paths and commands stay Level 0 and do not call cloud providers.
- WeChat and Feishu: candidate window remains visible and usable in chat inputs.
- Cloud failure: provider errors fall back to local correction/continuation without breaking commit.
- Keychain: API keys are resolved from Keychain, not persisted in provider JSON.

See `doc/mvp-acceptance.plan.md` for the full checklist.

## MVP Branch and PR Management

- Base release-readiness docs on `origin/dev`.
- Apply the pending provider runtime branch before finalizing docs so provider loading and Keychain behavior match the release candidate.
- Rebase docs work after runtime merges instead of merging stale docs over newer runtime, settings, privacy, or candidate panel changes.
- Keep release docs changes separate from runtime code changes and validate with `swift build`, `swift test`, and `git diff --check` before tagging or opening a release PR.
