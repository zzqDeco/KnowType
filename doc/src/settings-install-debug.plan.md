# Settings Install Debug

`ProviderProfilesView` is the SwiftUI settings surface for the MVP settings app.

## Layout

The view uses top-level native tabs:

- Input: read-only MVP composition and commit behavior.
- Candidates: candidate ordering and shortcut behavior.
- AI Provider: existing provider profile editor backed by `ProviderProfilesViewModel`.
- Privacy: Level 0 local-only reminders and technical-token preservation notes.
- Debug Install: local development install and log-inspection guidance.

## Provider Secrets

The AI Provider tab preserves the existing profile editing flow. The API key field remains a write-only `SecureField`: leaving it blank keeps the existing secret, while entering a new value writes through `SecretStore`. On macOS, the default path uses Keychain. Provider profile JSON stores `secretName` references only.

## Debug Install Guidance

The Debug Install tab documents the local developer loop at a high level:

- build and ad-hoc sign the bundle by default, or use `CODESIGN_IDENTITY` for Apple Development signing;
- copy `KnowType.app` to `~/Library/Input Methods`;
- refresh the input method process or log out and back in if macOS keeps stale registration state;
- enable KnowType in System Settings;
- inspect `KnowTypeInputMethodApp` messages with Console.app or `log stream`.

This guidance is intentionally not an installer UI and does not store or display API keys.
