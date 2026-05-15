# Settings Install Debug

`ProviderProfilesView` is the SwiftUI settings surface for the MVP settings app.

## Layout

The view uses top-level native tabs:

- Input: read-only MVP composition and commit behavior.
- Candidates: candidate ordering and shortcut behavior.
- Lexicons: local JSON/TSV directory status, entry counts, diagnostics, and missing-directory creation.
- AI Provider: provider profile editor and connection test backed by `ProviderProfilesViewModel`.
- Privacy: Level 0 local-only reminders and technical-token preservation notes.
- Debug Install: local development install and log-inspection guidance.

## Provider Secrets

The AI Provider tab preserves the existing profile editing flow. The API key field remains a write-only `SecureField`: leaving it blank keeps the existing secret, while entering a new value writes through `SecretStore`. On macOS, the default path uses Keychain. Provider profile JSON stores `secretName` references only.

The connection test uses the current draft profile and may use a typed API key for one request, but it does not save metadata or mutate `SecretStore`.

## Debug Install Guidance

The Debug Install tab documents the local developer loop through `DebugInstallGuidance`, a small testable settings-side source of truth:

- build and ad-hoc sign the bundle by default, or use `CODESIGN_IDENTITY` for Apple Development signing;
- copy `KnowType.app` to `~/Library/Input Methods`;
- request selection of `com.knowtype.inputmethod.KnowType.Mode` with `scripts/select-inputmethod.sh` after activating the target text app, while directing developers to `scripts/diagnose-inputmethod.sh` for the independent system status check;
- remind developers that the selection helper is only a preflight and final acceptance still requires typing a real probe in the target app;
- run `scripts/diagnose-inputmethod.sh` to verify bundle metadata, signing, packaged resources, Text Input Source registration, and local data paths without changing system state;
- use `scripts/select-inputmethod.sh --require-selected` as the selection preflight when the active text input context must already be KnowType;
- refresh the input method process or log out and back in if macOS keeps stale registration state;
- enable KnowType in System Settings;
- inspect `KnowTypeInputMethodApp` messages with Console.app or `log stream`.

This guidance is intentionally not an installer UI and does not store or display API keys.
