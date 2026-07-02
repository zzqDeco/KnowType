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
- Privacy guardrails: correction protects URLs, emails, paths, commands,
  code-like text, and protected app contexts from rewrite; real-time AI is hard
  disabled only for suspected secrets and filters secret-like candidate hints.
- Local lexicons: bundled seed lexicon plus user-owned JSON/TSV resources and a
  managed Rime Pinyin Simplified install path.

## Status

KnowType is currently a local MVP for development and manual testing. It
includes a Swift package, unit tests, a local InputMethodKit app bundle,
SwiftUI settings hosts, provider profile storage, Keychain-backed API keys, and
local dictionary tooling.

It is not yet a notarized installer, auto-updater, or App Store package.

GitHub Releases provide a Developer Preview DMG named
`KnowType-vX.Y.Z-macos-dev-preview.dmg`. It contains `KnowType.app`, a
command-file installer, a release manifest, and a SHA256 file. The DMG is not
Developer ID signed or notarized; macOS may require Control-click > Open or
Privacy & Security > Open Anyway before installation. The local MVP zip remains
available as a developer/debug asset.

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
purges stale `.Mode` development state, registers and enables the KnowType
parent input method plus the visible `.Hans` input mode from the installed app
context, and repairs history without moving KnowType ahead of the retained
current source. It does not rewrite selected preferences during install.
It does not launch the installed input-method host, does not auto-select
KnowType, and does not initialize Rime user data during install.
If macOS prelaunches the host while refreshing TIS or LaunchServices state, the
controller cold start still keeps Rime sessions, provider profiles, AI learning
and profile files, `ENV.md`, and `CORRECTION.md` lazy until real input, an AI
request, or explicit maintenance.
If an existing `KnowTypeInputMethodApp` process is running, the installer stops
before replacing files instead of killing it, because host shutdown can flush
Rime user data.
KnowType uses the mature macOS IMK shape: `com.knowtype.inputmethod.KnowType`
is the non-selectable parent input method, and
`com.knowtype.inputmethod.KnowType.Hans` is the only user-selectable visible
mode. Old `.Mode` records and parent-only selected/history rows are treated as
legacy cache entries and cleaned by the repair scripts. System Settings and the
menu bar should show exactly one user-selectable `KnowType` item.

`scripts/install-inputmethod.sh` defaults to a release build so local typing
tests exercise the optimized hot path. Rime runtime files are packaged inside
`KnowType.app`; if they are missing or fail to load, KnowType keeps raw input
usable and reports degraded conversion state instead of falling back to the
retired clean-room converter.

Overwrite installs create an app-level rollback backup under
`~/Library/Application Support/KnowType/Backups/` and record the active install
in `~/Library/Application Support/KnowType/install-state.json`. The backup
contains install artifacts only: `KnowType.app` and optional `KnowType.prefPane`.
It does not copy, restore, or mutate Rime userdb, provider profiles, Keychain
secrets, AI context documents, `~/.knowtype`, or local lexicons. First real
typing after manually selecting KnowType may initialize Rime as normal product
use; that is intentionally outside the install step.

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

After install, activate the target app, select KnowType from the macOS input
menu, or run the selection helper while that target app is active:

```bash
./scripts/select-inputmethod.sh --require-selected
```

Remove the local bundle:

```bash
./scripts/uninstall-inputmethod.sh
```

List or restore local rollback points:

```bash
./scripts/rollback-inputmethod.sh --list
./scripts/rollback-inputmethod.sh --latest
```

Local IME behavior must still be verified by typing in real host apps. See
[Local Input Method Testing](doc/local-inputmethod-testing.plan.md) and
[MVP Acceptance](doc/mvp-acceptance.plan.md) for the macOS policy, selection,
and manual acceptance flow.

For a GitHub Release DMG, verify the downloaded image with the published
`.sha256` file first:

```bash
cd ~/Downloads
shasum -a 256 -c KnowType-v0.2.3-macos-dev-preview.dmg.sha256
```

Open the DMG and run `Install KnowType.command`. If macOS blocks it, use
Control-click > Open, or open System Settings > Privacy & Security and choose
Open Anyway. The command records `source=dmg-dev-preview`, release commit/tag,
and manifest digest in diagnostics, but it does not launch the input method host
or perform a typing probe. Pass `--with-prefpane` only when the optional
compatibility System Settings pane is needed. Do not use a stale System Settings
sidebar entry unless the matching pane is installed.

The older local MVP zip can still be installed for developer debugging:

```bash
./scripts/install-inputmethod.sh --from-release-zip ~/Downloads/KnowType-v0.2.3-macos-local-mvp.zip
```

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
memory for the AI recommendation slot, `CORRECTION.md` stores user-editable AI
correction instructions, and `LEXICAL_PROFILE.md` mirrors the local top-K
lexical profile built from Rime userdb frequency plus recent KnowType commits
and selections plus bounded summaries of AI recommendations the user explicitly
accepted. Verified edits made immediately after accepting AI recommendations
are summarized separately as local AI feedback; ordinary Backspace is ignored
unless the cursor range proves the edit is inside the just-accepted AI span.
The full accepted-AI and feedback history is stored locally under Application
Support and is not injected directly into provider requests. The canonical
lexical profile JSON lives under
`~/Library/Application Support/KnowType/AI/`. Traditional input does not depend
on these files. Use `./scripts/accepted-learning.sh status`, `rebuild`, or
`clear --yes` to inspect, rebuild, or delete accepted-AI learning and feedback
data. Clear removes accepted-learning/feedback history, summary, and mirror
files and scrubs accepted-AI context from the lexical profile without deleting
Rime, provider, Keychain, ENV, or CORRECTION data.
Real-time AI recommendations use a task-specific suffix-generation prompt, have
a 10-second runtime timeout, prefer provider-level structured JSON schema output
when available, and emit privacy-preserving substate diagnostics through macOS
unified logging. While Rime is composing, the current page of Rime candidates is
not sent to the realtime AI request and unselected candidates are not treated as
the locked prefix. If no locked prefix exists yet, the AI response is a full
commit-ready recommendation based on raw input, context documents, and the
persistent lexical profile rather than a suffix attached to the first Rime
candidate. The logs distinguish schema fallback, structured decode failures,
prefix-lock sanitizer rejections, and too-short prefixes without recording raw
text. To inspect them, run
`log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType" && category == "ai"' --style compact`.

## Debug Diagnostics

Debug output is off by default. When enabled, diagnostics use privacy-safe
key/value fields only: ids, lengths, revisions, generations, reasons, elapsed
times, bundle ids, write modes, anchor sources, and handled/pass-through state.
They do not log raw input, preedit, candidate text, committed text, prompts,
provider output, context bodies, or API keys.

Use `KNOWTYPE_PERF_DEBUG=1` for a broad performance trace, or combine narrower
switches such as `KNOWTYPE_AI_DEBUG=1`, `KNOWTYPE_PANEL_DEBUG=1`,
`KNOWTYPE_TURN_DEBUG=1`, `KNOWTYPE_CLIENT_WRITE_DEBUG=1`, and
`KNOWTYPE_ANCHOR_DEBUG=1`.

```bash
launchctl setenv KNOWTYPE_PERF_DEBUG 1
log stream --predicate 'subsystem == "com.knowtype.inputmethod.KnowType"' --style compact
```

Clear debug variables after testing:

```bash
launchctl unsetenv KNOWTYPE_PERF_DEBUG
launchctl unsetenv KNOWTYPE_AI_DEBUG
launchctl unsetenv KNOWTYPE_PANEL_DEBUG
launchctl unsetenv KNOWTYPE_TURN_DEBUG
launchctl unsetenv KNOWTYPE_CLIENT_WRITE_DEBUG
launchctl unsetenv KNOWTYPE_ANCHOR_DEBUG
```

See [Debug Diagnostics](doc/debug-diagnostics.plan.md) for focused recipes for
first-key stalls, AI latency, candidate-panel residue, host writes, and anchor
placement.

## Input Behavior

| Shortcut | Behavior |
|---|---|
| `Space` | Commit the highlighted/current Rime candidate during composition; with no active composition, produce a normal space or pass it through in compatibility hosts. |
| `1...9` | Select Rime current-page candidates during native composition, even if the custom panel is hidden; with no active composition, produce ordinary digits or pass them through in compatibility hosts. |
| Arrow keys, `PageUp` / `PageDown`, `-` / `=`, `,` / `.` | Move within the current Rime page, page at candidate-list edges when another page is available, and otherwise let punctuation fall back to the normal commit path. Left/up from the first row lands on the previous page's last row. |
| `Return` / `Enter` | Commit the original raw composition. |
| `Tab` | Commit the AI recommendation when the second slot is ready; pending or unavailable AI keeps the composition active. |
| `0` | Commit the raw composition when correction candidates are visible; with no active composition, produce `0` or pass it through in compatibility hosts. |
| Plain punctuation | Let Rime handle composing schema keys first, then commit composition plus punctuation, insert punctuation directly, or pass it through in compatibility hosts when no composition is active. |
| `Option + .` | Toggle Chinese/English punctuation for the active input session. |
| `Option + /` | Toggle Chinese/ASCII text mode for the active input session; in terminal-style compatibility hosts, it switches between Chinese placeholder composition and idle ASCII passthrough. |
| `Option + 1` | Commit the ready AI recommendation explicitly. |
| `Option + 2...9` | Commit legacy continuation rows when they are present. |
| `Option + R` | Request explicit polish, the default rewrite path. |

Host compatibility is conservative. Standard AppKit-style text fields, browsers,
editors, IDEs, Electron shells, and unknown clients use inline composition with
attributed marked text by default, so raw preedit appears in the focused text
field. Terminal, iTerm, MacVim, and Emacs-style hosts default to idle ASCII
passthrough, so ordinary letters, digits, spaces, and punctuation stay owned by
the shell or editor until the session is switched with `Option + /`. In those
terminal-style hosts, Chinese composition uses a full-width-space attributed
marked-text placeholder to keep the host composition and candidate anchor alive;
the real raw/preedit string is shown in KnowType's candidate panel above the
candidates, then committed with `insertText`. A UserDefaults override can force
any bundle back to `commitOnlyComposition` when a host proves incompatible with
inline marked text.

The candidate panel shows Rime prefix candidates, a fixed AI recommendation
state row, terminal/override commit-only preedit when the host receives a
placeholder carrier, and raw input only when no suggestion is available. The
preedit row has no shortcut, selection, or commit action, and inline hosts do
not render it because the focused text field already shows preedit. The panel is
a compact AppKit panel using macOS material, system highlight colors,
mouse hover/click selection, scroll paging, and row accessibility labels. When a
provider is configured, Rime prefix candidates appear immediately and
provider-backed AI recommendations update
asynchronously. Provider failures do not show fixed local fallback text as if it
were AI output.

The first candidate slot is reserved for Rime conversion. The second slot is
reserved for AI recommendation state, so async provider results update that slot
without reordering the Rime candidate list. Ready AI uses Tab or explicit
Option-number rather than ordinary digit shortcuts. Pending, unavailable, or
ineligible AI states are shown as muted status rows without numeric shortcuts or
click commit behavior.

## Privacy

Level 0 correction protects text that should usually commit unchanged. It
prevents correction from rewriting protected content such as URLs, paths,
commands, code-like text, and protected app contexts.

Correction-protected examples include:

- URLs and `www.` addresses
- email-like input
- absolute, home-relative, and relative file paths
- command-like input such as `swift test` or `git status`
- code-like snippets containing braces, semicolons, or `=>`
- Terminal, iTerm, and Xcode sessions by bundle identifier

Real-time AI recommendation uses a narrower cloud privacy gate: `AI 已禁用`
appears only when raw input or confirmed prefix looks like a credential, such as
API keys, bearer tokens, JWTs, private keys, or password/token assignments.
Secret-like Rime candidate hints are filtered without disabling the whole
request.
Accepted AI learning uses the same secret-like hard block: credential-shaped
accepted text is not recorded, while ordinary technical text can be summarized
locally for future recommendations. AI feedback learning follows the same
secret-only block and records only verified post-accept edits.

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
