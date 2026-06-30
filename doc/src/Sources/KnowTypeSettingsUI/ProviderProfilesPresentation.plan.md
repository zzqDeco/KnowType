# ProviderProfilesPresentation

`ProviderProfilesPresentation.swift` contains testable presentation structs for the AI Provider settings tab.

## Responsibilities

- Map saved `ProviderProfile` rows into list item title/subtitle state.
- Map `ProviderProfileDraft` into editor labels, timeout text, and custom HTTP field visibility.
- Represent API key UI copy with the stored `secretName` reference only. Typed draft API key values are intentionally not copied into presentation state.
- Map `ProviderConnectionStatus` into progress, success, and failure display state.
- Keep validation and persistent error section visibility out of the SwiftUI view body.

The presenters do not mutate settings state, perform validation, call providers, or touch `SecretStore`. UI state belongs to `ProviderProfilesViewModel`; validation and credential editing policy belong to `ProviderProfileEditingPolicy`.
