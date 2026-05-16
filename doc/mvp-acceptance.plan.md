# KnowType MVP Acceptance

The MVP is accepted when these flows pass through package-level tests and then through manual macOS IMK verification.

## Build and Packaging Gate

- `swift build` passes on macOS with Swift 6.2.
- `swift test` passes before manual acceptance.
- CI checks local input-method script syntax, read-only help paths, and bundle packaging resources without installing or selecting the input method.
- `./scripts/build-inputmethod-bundle.sh` creates `dist/KnowType.app`.
- The built app includes SwiftPM resource bundles such as `KnowType_KnowTypeCore.bundle`, so bundled lexicons load after installation.
- `./scripts/install-inputmethod.sh` copies the bundle to `~/Library/Input Methods/KnowType.app`.
- `./scripts/diagnose-inputmethod.sh --strict` passes after install, confirming bundle metadata, signing, Text Input Source registration, and packaged resources.
- On macOS 15+, if Gatekeeper rejects an Apple Development build, generate and manually install the local SystemPolicyRule profile with `./scripts/create-local-system-policy-profile.sh --open`, then rerun diagnostics before judging selection behavior.
- Activate the target text app, then use `./scripts/select-inputmethod.sh --require-selected --no-diagnose` as a selection preflight after diagnostics have already run. Acceptance still requires typing a real probe in that target app.
- `./scripts/accept-inputmethod-local.sh` runs the repeatable local acceptance harness. By default it performs script/profile smoke, diagnostics, and report-template generation without selecting an input source; pass `--install` or `--select` only when intentionally mutating the local macOS session.
- KnowType can be enabled from System Settings > Keyboard > Text Input > Input Sources.
- `./scripts/uninstall-inputmethod.sh` removes the local bundle after verification.
- This gate covers local MVP packaging only; signed installer, notarization, update flow, and App Store packaging are follow-up work.

## Automated Scenarios

- Chinese typo correction: `wo jue de zhege fagnan -> 我觉得这个方案`
- Mixed technical input: `zhege api latnecy youdian gao -> 这个 API latency 有点高`
- English correction: `I thikn this approch -> I think this approach`
- Level 0 path input: `/Users/zq/project/KnowType` is not rewritten
- Explicit polish only: `Option + R` is the only default path that requests rewriting
- Candidate panel rendering keeps raw input, locked prefix, and continuation as separate semantic rows while presenting a flat native-style list.
- Candidate panel shortcuts match commit behavior: `⇥` for the first continuation and `⌥2` for the second continuation.
- Runtime lexicon directory loading can add user-owned JSON/TSV entries without changing Swift source.
- Settings lexicon status reports the local lexicon directory, loaded entries, and diagnostics.
- Provider profiles round-trip without API key values.
- Provider resolution pulls secrets through `SecretStore`.

## Manual macOS Scenarios

The harness writes `dist/KnowTypeLocalIMEAcceptance.md` with these probes and
evidence fields. Fill that report during local acceptance instead of treating a
successful script run as proof of target-app typing behavior.

- TextEdit:
  - Type `wo jue de zhege fagnan`.
  - Candidate window appears near the caret as a compact flat list, without preview text or section headers.
  - `Space` commits `我觉得这个方案` only.
  - `Tab` commits the locked prefix plus first continuation.
- Safari:
  - In a search field or text area, type mixed Chinese/English input such as `zhege api latnecy youdian gao`.
  - `Tab` commits the locked prefix plus first continuation.
  - `API` remains uppercase and `latency` remains protected as a technical token.
- Chrome:
  - Repeat the Safari flow in a normal web text field.
  - Candidate window placement and shortcut handling remain usable.
- Xcode:
  - Type code-like or technical input containing `API`, `JSON`, `macOS`, `InputMethodKit`, `snake_case`, or `camelCase`.
  - Technical tokens and identifiers are preserved.
  - Code-like snippets containing braces, semicolons, or `=>` are treated as Level 0.
- Terminal:
  - Type `/Users/zq/project/KnowType`, `~/project`, or a command-like line.
  - Input stays Level 0, does not request cloud suggestions, and commits unchanged.
- WeChat:
  - Type normal chat text and verify the candidate window remains visible and usable in the chat input field.
  - `Space`, `Tab`, `Option+1`, and `Option+R` do not conflict with the host app in the tested field.
- Feishu:
  - Repeat the WeChat chat-field flow.
  - Candidate window remains visible and usable.

## Provider and Privacy Scenarios

- Supported provider kinds are visible in configuration docs and adapter tests:
  - `openai_chat`
  - `openai_responses`
  - `anthropic_messages`
  - `gemini_native`
  - `ollama_native`
  - `custom_http`
- Provider profile JSON stores `secretName` for API keys, never the API key value itself. Custom headers are persisted as configured and should not contain secrets in the MVP.
- API keys are created, read, and deleted through Keychain-backed `SecretStore` on macOS.
- Provider runtime loading selects the adapter from `ProviderKind` and normalizes all responses into `LLMResponse`.
- No-provider fallback:
  - Disable provider configuration.
  - Local correction still returns a prefix candidate.
  - Local fallback continuation is used when available.
- Configured provider failure:
  - Simulate a provider error, timeout, invalid endpoint, or invalid response.
  - Local correction still returns a prefix candidate.
  - Continuation rows may be absent; KnowType must not show mock AI continuation text as if it came from the configured provider.
  - Typing and prefix commit remain available.
- Level 0 protected input still produces no continuation candidates.
- Level 0 no-cloud:
  - URLs, emails, paths, command-like input, code-like snippets, Terminal, iTerm, and Xcode contexts must use the no-provider pipeline.
  - No HTTP request is made for Level 0 input.
  - The commit result preserves the original protected text.

## Release Notes Boundary

MVP release notes may claim:

- Local Swift package build and test workflow.
- Local macOS InputMethodKit bundle build/install scripts.
- Custom candidate panel model and renderer contract.
- Runtime provider profile resolution and adapter factory.
- Keychain-backed API key storage for macOS.
- Level 0 privacy path for protected text and terminal contexts.

MVP release notes must not claim:

- Signed installer, notarization, auto-update, or App Store distribution.
- Full production settings UI unless the settings slice is merged into the release branch.
- Complete pinyin or shuangpin decoding.
- Guaranteed compatibility with every macOS app outside the manual acceptance matrix.

## Current Automation

`Tests/KnowTypeInputMethodTests/MVPAcceptanceTests.swift` verifies the product-level flow through `InputMethodPipeline` and `InputCompositionController`.
`Tests/KnowTypeInputMethodTests/CandidatePanelRendererTests.swift` verifies candidate window render rows and shortcut labels.
`Tests/KnowTypeProvidersTests/ProviderProfileTests.swift` verifies profile persistence and secret-store resolution.
