# KnowType

[中文](README_CN.md)

KnowType is a macOS Chinese/English input method with an AI layer built around one product rule: it can correct what you are typing, but continuation must not rewrite the prefix you have already confirmed.

In practical terms, KnowType tries to make the first half more accurate and the second half smoother. It decodes imperfect pinyin or mixed Chinese/English input into a locked prefix, then asks the local engine or a configured provider for continuation text that starts after that prefix.

Chinese name: 知键.

## What It Does

- **Chinese input first**: pinyin decoding, compact pinyin segmentation, typo normalization, same-pinyin candidates, common initial abbreviations such as `sm`/`zmb`/`wsm`, and partial-syllable input.
- **Local candidate learning**: recent prefix choices can boost candidate ranking across input-method restarts without being sent to providers.
- **Prefix-locked AI continuation**: continuation candidates append after the locked prefix; explicit polish is the only path that may rewrite existing text.
- **Native macOS input flow**: marked text, candidate selection, paging, punctuation handling, and an AppKit candidate panel anchored near the text caret.
- **Provider-compatible by design**: OpenAI-compatible chat, OpenAI Responses, Anthropic Messages, Gemini native, Ollama native, and custom HTTP profiles all normalize into one provider interface.
- **Local privacy guardrails**: URLs, emails, paths, commands, code-like text, and protected app contexts use the no-provider path.

## Product Rule

KnowType follows this pipeline:

```text
raw input -> correction -> locked prefix -> continuation -> commit
```

For example:

```text
raw input:        wo jue de zhege fagnan
locked prefix:    我觉得这个方案
continuation:     还有进一步优化空间
commit with Tab:  我觉得这个方案还有进一步优化空间
```

The AI candidate is only `还有进一步优化空间`. It is not allowed to turn the prefix into a different sentence such as `我认为当前方案...` unless the user explicitly triggers polish.

## Current MVP Scope

KnowType is currently a local MVP for development and manual testing. It includes:

- a Swift package with core correction, provider adapters, and input-method interaction logic
- a local InputMethodKit app bundle built into `dist/KnowType.app`
- a compact custom candidate panel instead of relying on `IMKCandidates` as the main UI
- a clean-room pinyin engine for MVP Chinese input coverage
- SwiftUI settings for provider profiles, local lexicon status, privacy summary, input/candidate behavior, and debug install notes
- a Debug Install settings tab that mirrors the local build, install, diagnose, selection, and logging commands
- Keychain-backed API key storage for provider profiles
- local candidate-learning history stored separately from provider configuration

It is not yet a signed installer, notarized release, or App Store package.

## Repository Layout

```text
Sources/KnowTypeCore/          Product models, protection rules, correction, continuation
Sources/KnowTypeProviders/     Provider profiles, runtime loading, adapters, HTTP normalization
Sources/KnowTypeInputMethod/   IMK controller, session actions, candidate panel, key behavior
Sources/KnowTypeInputMethodApp Local macOS input-method app entry point
Sources/KnowTypeSettingsApp/   SwiftUI settings and provider profile editing
Tests/                         Unit tests for core behavior, providers, and input method logic
doc/                           Current architecture, interface, acceptance, and source notes
plan/                          Active or recently delivered implementation plans
Resources/                     Dictionaries, schema notes, and future bundled assets
```

See [doc/README.md](doc/README.md) for the documentation map.

## Build And Local Install

Requirements:

- macOS 13 or newer for the local InputMethodKit bundle
- Swift 6.2 toolchain

Run package checks:

```bash
swift build
swift test
```

Build and install the local input-method bundle:

```bash
./scripts/build-inputmethod-bundle.sh
./scripts/install-inputmethod.sh
```

Run the installed-bundle diagnostic before manual typing checks:

```bash
./scripts/diagnose-inputmethod.sh
```

Detailed install, signing, Text Input Source, and troubleshooting notes live in [doc/src/scripts/inputmethod-diagnostics.plan.md](doc/src/scripts/inputmethod-diagnostics.plan.md).

To remove the local bundle:

```bash
./scripts/uninstall-inputmethod.sh
```

## Demo Without Installing

You can run the package-level flow before installing the input method:

```bash
swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan
swift run knowtype-demo --locale mixed --action tab zhege api latnecy youdian gao
swift run knowtype-demo --locale en-US --action tab I thikn this approch
```

## Provider Configuration

KnowType loads model providers through `ProviderProfile` and `ProviderFactory`. Profiles are stored as JSON metadata; API keys are stored separately.

Default profile file:

```text
~/Library/Application Support/KnowType/providers.json
```

Local candidate-learning history is stored at:

```text
~/Library/Application Support/KnowType/user-selection-history.json
```

Local JSON/TSV lexicons are read from:

```text
~/Library/Application Support/KnowType/Lexicons
```

The settings app shows whether this directory exists, how many lexicon entries loaded, and any resource diagnostics. It can create missing directories for you. Missing directories are allowed; KnowType falls back to the bundled seed lexicon.
For development, `KNOWTYPE_LEXICON_DIR` and colon-separated `KNOWTYPE_LEXICON_DIRS` are also recognized before the default directory.

Profile fields:

```text
id, displayName, kind, baseURL, model, timeoutSeconds, headers,
secretName, customBodyTemplate, customResponsePath, isDefault
```

`secretName` resolves through `SecretStore`. On macOS, `KeychainSecretStore` stores API keys in Keychain under the `KnowType` service. Provider JSON stores the secret name, not the secret value.

Custom `headers` are saved in provider JSON exactly as configured. Do not put bearer tokens, API keys, or other secrets in custom headers for the MVP; use the profile API key field and Keychain-backed secret storage instead.

When `providers.json` is missing or empty, KnowType seeds a local OpenAI-compatible default at `http://127.0.0.1:8317/v1`. The model may stay blank for `/v1/models` discovery. No API key is embedded in source or profile JSON; save one in settings if your local runtime requires it.

The AI Provider tab includes a connection test for the current draft profile. It uses a typed draft API key only for that test request, or reuses an existing Keychain secret when the key field is blank. It does not save profile JSON or mutate Keychain.

Supported provider kinds:

- `openai_chat`: `/v1/chat/completions`
- `openai_responses`: `/v1/responses`
- `anthropic_messages`: `/v1/messages`
- `gemini_native`: Gemini `models.generateContent`
- `ollama_native`: Ollama `/api/chat`
- `custom_http`: templated request body plus response path extraction

Local OpenAI-compatible runtimes may leave the model blank so KnowType can discover models from `/v1/models`. Remote OpenAI-compatible profiles require an explicit model ID. Custom HTTP profiles can omit the API key for local proxy endpoints.

## Input Behavior

- `Space`: commit the selected prefix candidate.
- `Tab`: commit the selected prefix plus the first or selected continuation.
- `0`: commit the raw composition when correction candidates are visible.
- plain punctuation: commit composition plus punctuation, or insert punctuation directly when there is no composition.
- `Option + .`: toggle Chinese/English punctuation for the active input session.
- `Option + number`: commit the selected prefix plus the mapped continuation. `Option + 1` matches the first continuation and is displayed as `⇥` because `Tab` commits it directly.
- `Option + R`: request polish; this is the explicit rewrite path.

The Input settings tab persists default punctuation language and symbol width for normal apps and code-style apps. Terminal, iTerm, Xcode, VS Code, and Codex desktop start with the code-app defaults while keeping the Chinese text pipeline available.

The candidate panel shows prefix candidates first and continuation candidates after them. Candidate rows are paged in 9-row windows. Recent prefix selections can influence local candidate order across input-method restarts. When a provider is configured, KnowType publishes local prefix candidates immediately and updates continuation rows when the provider response arrives. If that provider fails or returns no usable continuation, KnowType keeps the traditional prefix candidates and does not substitute fixed local fallback text as AI output.

## Privacy Baseline

Level 0 input must not call cloud providers. It uses the no-provider path and clears cloud continuation candidates.

Protected examples include:

- URLs and `www.` addresses
- email-like input
- absolute, home-relative, and relative file paths
- command-like input such as `swift test` or `git status`
- code-like snippets containing braces, semicolons, or `=>`
- Terminal, iTerm, and Xcode sessions by bundle identifier

Technical tokens such as `API`, `JSON`, `FastAPI`, `iOS`, `macOS`, `InputMethodKit`, `snake_case`, and `camelCase` are preserved or canonicalized.

## Manual MVP Acceptance

Before tagging an MVP build, run:

```bash
swift build
swift test
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict
./scripts/select-inputmethod.sh --require-selected
```

Then manually type a real probe in each target app:

- TextEdit: candidate window appears near the caret; `Space` commits prefix only.
- Safari and Chrome: text fields accept `Tab` for prefix plus first continuation.
- Xcode: technical tokens and code-like identifiers are preserved.
- Terminal: paths and commands stay Level 0 and do not call providers.
- WeChat and Feishu: candidate window remains visible and usable in chat inputs.
- Provider failure: local correction still works and commit is not blocked.
- Keychain: API keys are resolved from Keychain, not persisted in provider JSON.

The full checklist is in [doc/mvp-acceptance.plan.md](doc/mvp-acceptance.plan.md).

## Branch Workflow

- `main`: stable branch.
- `dev`: integration branch.
- topic branches: `feature/<desc>`, `fix/<desc>`, `docs/<desc>`, `refactor/<desc>`, `test/<desc>`, `release/<version>`.

Use Conventional Commits and open topic PRs into `dev` first. Keep documentation-only changes separate from runtime code changes when possible.
