# KnowType

[![CI](https://github.com/zzqDeco/KnowType/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/zzqDeco/KnowType/actions/workflows/ci.yml)

[中文](README_CN.md)

KnowType, Chinese name 知键, is a macOS Chinese/English input method with
AI-assisted continuation. It is written in Swift and built around a strict
product rule: correction may improve the prefix you are typing, but
continuation must not rewrite the locked prefix you have already accepted.

| Area | Current state |
|---|---|
| Language | Swift 6.2 |
| Platform | macOS 13+ |
| Core package | Swift Package Manager |
| Input method host | AppKit + InputMethodKit |
| Settings UI | SwiftUI |
| Integration branch | `dev` |

## Why KnowType

KnowType separates "make what I typed correct" from "continue after what I
accepted".

```text
raw input -> correction -> locked prefix -> continuation -> commit
```

Example:

```text
raw input:        wo jue de zhege fagnan
locked prefix:    我觉得这个方案
continuation:     还有进一步优化空间
Tab commit:       我觉得这个方案还有进一步优化空间
```

The AI continuation is only `还有进一步优化空间`. It is not allowed to turn
the locked prefix into another sentence unless the user explicitly triggers
polish.

## Features

- Chinese input first: the production IMK hot path uses bundled `librime` for
  synchronous pinyin conversion, Space commit, number selection, and paging.
- Local candidate learning: recent prefix choices can boost local ranking across
  input-method restarts without being sent to providers.
- Prefix-locked AI recommendation: the first candidate stays Rime conversion,
  the second slot is reserved for AI, and explicit polish is the only rewrite
  path.
- macOS input method flow: marked text, candidate selection, paging,
  punctuation handling, and a compact native-style AppKit candidate panel that
  stays above Spotlight/search overlays.
- Provider compatibility: OpenAI-compatible chat, OpenAI Responses, Anthropic
  Messages, Gemini native, Ollama native, and custom HTTP profiles normalize
  into one provider interface.
- Privacy guardrails: URLs, emails, paths, commands, code-like text, and
  protected app contexts use the no-provider Level 0 path.
- Local lexicons: bundled seed lexicon plus user-owned JSON/TSV resources and a
  managed Rime Pinyin Simplified install path.

## Status

KnowType is currently a local MVP for development and manual testing. It
includes a Swift package, unit tests, a local InputMethodKit app bundle,
SwiftUI settings hosts, provider profile storage, Keychain-backed API keys, and
local dictionary tooling.

It is not yet a signed installer, notarized release, auto-updater, or App Store
package.

GitHub Releases may provide a local MVP zip named
`KnowType-vX.Y.Z-macos-local-mvp.zip`. That archive contains the ad-hoc signed
`KnowType.app` input method bundle and `KnowType.prefPane`, plus a SHA256 file
and release manifest. It is still local MVP packaging, not a notarized installer.

## Quick Start

Requirements:

- macOS 13 or newer
- Swift 6.2 toolchain

Build and test:

```bash
swift build
swift test
```

Try the package-level flow without installing the input method:

```bash
swift run knowtype-demo --locale zh-CN --action tab wo jue de zhege fagnan
swift run knowtype-demo --locale mixed --action tab zhege api latnecy youdian gao
swift run knowtype-demo --locale en-US --action tab I thikn this approch
```

## Install Local IME

Build and install the local development bundle:

```bash
./scripts/build-inputmethod-bundle.sh --configuration release
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh
```

The local installer refreshes the traditional InputMethodKit app registration,
purges stale `.Mode` development state, restores the System Settings
third-party parent anchor plus the visible `.Hans` mode, and launches the
installed app so registration and best-effort selection run from the app
context macOS uses for input switching. KnowType follows the mature component
mode shape used by Squirrel, McBopomofo, and macSKK: the parent id is
`com.knowtype.inputmethod.KnowType`, and the visible input source is
`com.knowtype.inputmethod.KnowType.Hans`.

`scripts/install-inputmethod.sh` defaults to a release build so local typing
tests exercise the optimized hot path. Rime runtime files are packaged inside
`KnowType.app`; if they are missing or fail to load, KnowType keeps raw input
usable and reports degraded conversion state instead of falling back to the
retired clean-room converter.

KnowType-specific settings follow the native IMK input-method pattern used by
McBopomofo and OpenVanilla: choose KnowType from the macOS input menu and select
`KnowType Settings...`. It opens a macOS-native sidebar and grouped settings
window using Simplified Chinese on Chinese macOS locales and English fallback
strings on non-Chinese locales. The local install does not install a standalone
settings app. The default install removes any stale local compatibility
`KnowType.prefPane` so it cannot drift out of sync. A matching compatibility pane
is only built and installed when `./scripts/install-inputmethod.sh --with-prefpane`
is used. If System Settings still shows a `KnowType` sidebar entry after a
default install, it is stale macOS PreferencePane cache state; run the install
script again or `./scripts/uninstall-inputmethod.sh` to refresh the cache, then
reopen System Settings.

After the first install or a mode-id migration, macOS may still require the
System Settings input-source approval path. Open System Settings > Keyboard >
Input Sources, remove stale KnowType rows, add `知键` / `KnowType` again, and
click Allow if macOS asks. If the menu still shows stale entries, log out and
back in to clear the Text Input Source cache. This follows the same boundary
used by mature IMK input methods: installation uses TIS registration and
enablement, while System Settings writes the protected third-party input-source
approval rows.

Select KnowType in the active target app when needed:

```bash
./scripts/select-inputmethod.sh --require-selected
```

Remove the local bundle:

```bash
./scripts/uninstall-inputmethod.sh
```

Local IME behavior must still be verified by typing in real host apps. See
[Local Input Method Testing](doc/local-inputmethod-testing.plan.md) and
[MVP Acceptance](doc/mvp-acceptance.plan.md) for the macOS policy, selection,
and manual acceptance flow.

For a GitHub Release zip, verify the downloaded archive with the published
`.sha256` file first. Then expand it, copy `KnowType.app` to
`~/Library/Input Methods/`, and use the input menu's `KnowType Settings...`
entry for configuration. `KnowType.prefPane` is a compatibility settings host
and may be copied to `~/Library/PreferencePanes/` when that fallback is needed.
Do not use a stale System Settings sidebar entry unless the matching pane is
installed.
Run the same local diagnostics/manual typing acceptance from a source checkout
when available.

## Configuration

Provider profiles are stored as JSON metadata; API keys are stored separately.

```text
~/Library/Application Support/KnowType/providers.json
```

Local candidate-learning history:

```text
~/Library/Application Support/KnowType/user-selection-history.json
```

Local JSON/TSV lexicons:

```text
~/Library/Application Support/KnowType/Lexicons
```

`KNOWTYPE_LEXICON_DIR` and colon-separated `KNOWTYPE_LEXICON_DIRS` can add
development lexicon directories before the default directory.

Install the recommended managed lexicon pack:

```bash
scripts/install-lexicon-pack.sh rime-pinyin-simp
```

The installer downloads a pinned Apache-2.0 Rime dictionary, verifies SHA256,
converts it into KnowType TSV, and writes local metadata beside the TSV.
Third-party bulk dictionary data is not committed to this repository.

When `providers.json` is missing or empty, KnowType seeds a local
OpenAI-compatible profile at `http://127.0.0.1:8317/v1` with no embedded API
key. Remote OpenAI-compatible profiles require an explicit model ID; local
OpenAI-compatible profiles may leave the model blank for `/v1/models`
discovery.

AI context files live under `~/.knowtype/`. `ENV.md` stores local context
memory for the AI recommendation slot, and `CORRECTION.md` stores user-editable
AI correction instructions. Traditional input does not depend on either file.

## Input Behavior

| Shortcut | Behavior |
|---|---|
| `Space` | Commit the highlighted/current Rime candidate, or raw input when Rime is unavailable. |
| `1...9` | Select Rime current-page candidates during native composition, even if the custom panel is hidden. |
| Arrow keys, `PageUp` / `PageDown`, `-` / `=`, `,` / `.` | Move within the current Rime page, page at candidate-list edges when another page is available, and otherwise let punctuation fall back to the normal commit path. Left/up from the first row lands on the previous page's last row. |
| `Return` / `Enter` | Commit the original raw composition. |
| `Tab` | Commit the AI recommendation when the second slot is ready; pending or unavailable AI keeps the composition active. |
| `0` | Commit the raw composition when correction candidates are visible. |
| Plain punctuation | Let Rime handle composing schema keys first, then commit composition plus punctuation or insert punctuation directly when Rime declines. |
| `Option + .` | Toggle Chinese/English punctuation for the active input session. |
| `Option + 1` | Commit the ready AI recommendation explicitly. |
| `Option + 2...9` | Commit legacy continuation rows when they are present. |
| `Option + R` | Request explicit polish, the default rewrite path. |

The candidate panel shows Rime prefix candidates, a fixed AI recommendation
state row, and raw input only when no suggestion is available. It is a compact
AppKit panel using macOS material, system highlight colors, mouse hover/click
selection, scroll paging, and row accessibility labels. When a provider is
configured, Rime prefix candidates appear immediately and provider-backed AI
recommendations update asynchronously. Provider failures do not show fixed
local fallback text as if it were AI output.

The first candidate slot is reserved for Rime conversion. The second slot is
reserved for AI recommendation state, so async provider results update that slot
without reordering the Rime candidate list. Ready AI uses Tab or explicit
Option-number rather than ordinary digit shortcuts. Pending, unavailable, or
ineligible AI states are shown as muted status rows without numeric shortcuts or
click commit behavior.

## Privacy

Level 0 input must not call cloud providers. It uses the no-provider path and
clears continuation candidates.

Protected examples include:

- URLs and `www.` addresses
- email-like input
- absolute, home-relative, and relative file paths
- command-like input such as `swift test` or `git status`
- code-like snippets containing braces, semicolons, or `=>`
- Terminal, iTerm, and Xcode sessions by bundle identifier

Technical tokens such as `API`, `JSON`, `FastAPI`, `iOS`, `macOS`,
`InputMethodKit`, `snake_case`, and `camelCase` are preserved or canonicalized.

## Documentation

- [Documentation map](doc/README.md)
- [Architecture](doc/architecture.plan.md)
- [Interfaces](doc/interfaces.plan.md)
- [MVP acceptance](doc/mvp-acceptance.plan.md)
- [Source notes](doc/src/README.md)
- [Implementation plans](plan/README.md)

## Development

Repository layout:

```text
Sources/KnowTypeCore/           Product models, protection, correction, continuation
Sources/KnowTypeProviders/      Provider profiles, runtime loading, adapters
Sources/KnowTypeAI/             AI recommendation, context memory, correction instructions
Sources/KnowTypeInputMethod/    IMK controller, session actions, candidate panel
Sources/KnowTypeInputMethodApp/ Local macOS input-method app entry point
Sources/KnowTypeSettingsUI/     Shared SwiftUI settings UI
Sources/KnowTypeSettingsApp/    Developer preview settings app host
Sources/KnowTypePreferencePane/ Compatibility PreferencePane host
Tests/                          Unit tests
doc/                            Current engineering documentation
plan/                           Active and recently delivered implementation plans
Resources/                      macOS bundle resources
```

Branch workflow:

- `main`: stable branch
- `dev`: integration branch
- topic branches: `feature/<desc>`, `fix/<desc>`, `docs/<desc>`,
  `refactor/<desc>`, `test/<desc>`, `release/<version>`

Use Conventional Commits and open topic PRs into `dev` first. For code changes,
run `swift test`; for input-method hot-path changes also run
`./scripts/perf-input-hotpath.sh`. For documentation-only changes, run at least
`git diff --check` and keep indexes in `doc/` and `plan/` synchronized.

## Roadmap / Non-Goals

Current non-goals:

- signed installer, notarization, auto-update, or App Store distribution
- complete real-world pinyin dictionary coverage without licensed local lexicons
- universal compatibility claims for every macOS host app
- using local fallback continuation as fake configured-provider output
- rewriting locked prefixes except through explicit polish

## License

License not declared yet.
