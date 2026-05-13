# Preferences Install Debug

## Goal

Split the SwiftUI settings app into mature MVP settings areas while keeping provider profile editing behavior unchanged.

## Scope

- Add native settings tabs for Input, Candidates, AI Provider, Privacy, and Debug Install.
- Keep `ProviderProfilesViewModel` as the provider-editing state owner.
- Keep API key values out of provider JSON; the AI Provider UI explains that Keychain-backed secret storage stores the value while profile JSON stores only `secretName`.
- Add high-level local development install/debug guidance for building, ad-hoc or Apple Development signing, installing to `~/Library/Input Methods`, refreshing macOS input source registration, enabling in System Settings, and inspecting logs.

## Non-Goals

- No changes to core correction, continuation, privacy classification, candidate selection, or IMK input logic.
- No signed installer, notarization, updater, or App Store packaging.
- No hardcoded API keys or provider-specific secrets in source or docs.

## Verification

- Run `swift test --filter KnowTypeSettingsAppTests`.
- Manual UI follow-up: launch `KnowTypeSettingsApp` and confirm the provider profile editor still saves existing profiles from the AI Provider tab.
