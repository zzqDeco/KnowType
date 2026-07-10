# Settings Install Debug

`ProviderProfilesView` is part of the reusable SwiftUI settings surface. The
primary user host is the InputMethodKit preferences window opened from the
input-method menu. The settings app remains a developer preview host, and
`KnowType.prefPane` is a compatibility fallback.

## Layout

The view uses top-level native tabs:

- Input: MVP composition behavior, punctuation defaults, symbol width, and Rime commit behavior.
- Candidates: candidate page size, panel layout preference, ordering, and shortcut behavior.
- Rime/User Data: local JSON/TSV directory status, entry counts, diagnostics, and missing-directory creation.
- AI Provider: continuation controls, provider profile editor, and connection test backed by `ProviderProfilesViewModel`.
- Privacy: current cloud/local continuation status, Level 0 local-only reminders, and technical-token preservation notes.
- Diagnostics: local development install and log-inspection guidance.

## Provider Secrets

The AI Provider tab preserves the existing profile editing flow. The API key
field remains a write-only `SecureField`: leaving it blank keeps a resolvable
secret only for the same provider kind and endpoint scope, while entering a new
value writes a new immutable reference through `SecretStore`. On macOS, the
default path uses Keychain. Provider profile JSON stores `secretName` references
only.

The connection test uses the current draft profile and may use a typed API key
for one request, but it does not save metadata or mutate `SecretStore`. Stale
provider-file baselines fail closed and refresh saved profiles without replacing
the draft.

Provider and lexicon display decisions that are easy to regress now live in testable presenter structs:

- `ProviderProfilesPresentation.swift` owns provider row labels, draft editor labels, secret-reference copy, connection status display state, validation visibility, and last-error visibility.
- `LexiconSettingsPresentation.swift` owns local lexicon count rows, missing-directory action visibility, directory status rows, diagnostics, and format guidance copy.

## Diagnostics Guidance

The Diagnostics tab documents the local developer loop through `DebugInstallGuidance`, a small testable settings-side source of truth:

- build and Apple Development-sign the bundle by default when a local identity exists, while still allowing `CODESIGN_IDENTITY=-` for explicit ad-hoc local testing;
- copy `KnowType.app` to `~/Library/Input Methods` and use the input-source helper for registration/enabling without launching the installed input-method host or running a typing probe;
- optionally install `KnowType.prefPane` to `~/Library/PreferencePanes` as a compatibility settings fallback when `--with-prefpane` is requested;
- request selection of the single `com.knowtype.inputmethod.KnowType` input source with `scripts/select-inputmethod.sh` only as a retry/preflight after activating the target text app, while directing developers to `scripts/diagnose-inputmethod.sh` for the independent system status check;
- remind developers that the selection script is only a preflight and final acceptance still requires typing a real probe in the target app;
- run `scripts/diagnose-inputmethod.sh` to verify bundle metadata, signing, packaged resources, Text Input Source registration, and local data paths without changing system state;
- run `scripts/repair-inputmethod-selection.sh` when stale LaunchServices records, legacy `.Hans` / `.Mode` TIS rows, or stale selected/history rows make selection bounce back to another source;
- use `scripts/select-inputmethod.sh --require-selected` as the installed-app selection preflight before typing in the active text app;
- log out and back in only after the repair script still leaves macOS on stale session state;
- approve the macOS System Settings prompt that asks whether to allow `知键` to enable `KnowType`, then enable KnowType in System Settings;
- inspect `KnowTypeInputMethodApp`, Gatekeeper, and input-source sandbox messages with `scripts/diagnose-inputmethod.sh --strict --logs`, Console.app, or `log stream`.

Provider endpoint diagnostics keep scheme, host, port, and path while removing
userinfo, query, and fragment. This guidance is intentionally not an installer
UI and does not store or display API keys.
