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
Sources/KnowTypeInputMethod/   Input-method interaction, candidate panel, IMK bootstrap
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

During local input, KnowType marks the composing text in the client app first, then shows a compact macOS-style candidate panel anchored to the caret when the client exposes a usable text rect. The anchor lookup falls back through marked/selected range starts and ends, line-height rectangles, and finally the pointer so the panel still appears in host apps with incomplete IMK geometry. `Space` replaces the marked text with the best corrected prefix, while `Tab` replaces it with prefix plus the first continuation.

The local correction path includes a small clean-room pinyin engine for MVP testing. It supports the documented full-pinyin examples, compact input such as `wojuedezhegefagnan`, unfinished compact-pinyin prefixes such as `xianz -> 现在`, common `fangan` typos, high-frequency initial abbreviations such as `wsm -> 为什么`, multiple prefix candidates like `方案/方法/方向`, and technical-token passthrough for mixed Chinese/English text. Short pinyin-initial and compact-prefix inputs can also ask the configured provider for correction candidates without letting cloud results override stronger local candidates. In `en-US` mode, local correction stays on English spellcheck instead of decoding pinyin.

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

The settings app edits provider profiles for OpenAI, Anthropic, Gemini, Ollama, and custom HTTP endpoints. Cloud profiles require a new key or an existing Keychain secret. Remote OpenAI-compatible profiles require an explicit model ID and reject discovery placeholders such as `<model-id>`; local OpenAI-compatible runtimes may leave the model blank for local `/v1/models` discovery. Custom HTTP profiles may omit the API key for local proxy endpoints, or store an optional profile-scoped key when one is entered. Switching a profile to a local/no-secret provider clears stale non-local secret references when no other saved profile still references them; leaving the API key blank on an existing local OpenAI-compatible profile keeps its optional key only when the Keychain item still resolves.

The settings app is split into MVP sections for Input, Candidates, AI Provider, Privacy, and Debug Install. The Debug Install section summarizes the local development flow: build/sign the input method bundle, optionally pass an Apple Development identity through `CODESIGN_IDENTITY`, install it to `~/Library/Input Methods`, refresh macOS input source registration if needed, enable KnowType in System Settings, and inspect `KnowTypeInputMethodApp` logs with Console.app or `log stream`.

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
- `Option + number`: commit the selected prefix plus the continuation shown with that shortcut. `Option + 1` matches the first continuation, which is displayed with the `⇥` shortcut because `Tab` commits it directly.
- `Option + R`: request polish; this is the only default path that may rewrite the prefix.

The candidate panel is intentionally flat: prefix candidates appear first, continuation candidates appear after them, and raw input is shown only when there are no correction candidates yet. When a provider is configured, the immediate local pass shows prefix candidates only; continuation rows are published when the provider result arrives. Local fallback continuations are used when no provider is configured or the provider path fails.

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

- TextEdit: candidate window appears near the caret; `Space` commits prefix only.
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
