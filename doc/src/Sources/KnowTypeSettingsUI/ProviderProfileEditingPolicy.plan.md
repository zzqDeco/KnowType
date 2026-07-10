# ProviderProfileEditingPolicy

## Responsibility

`ProviderProfileEditingPolicy` owns provider-profile editing rules that are not
SwiftUI state:

- Draft validation for display name, HTTP(S) base URL, model requirements,
  timeout, and custom HTTP template fields.
- Save-plan construction for updated profiles, default-provider exclusivity,
  immutable credential references, post-save draft state, and staged metadata.
- Secret mutation decisions for required cloud keys, optional local/custom HTTP
  keys, blank-key keep or clear behavior, and provider kind or endpoint changes.
- Transient connection-test `ProviderConfiguration` construction without saving
  draft secrets.
- Secret mutation planning, including shared-secret protection and identifying
  new versus retired references for transactional sequencing in the ViewModel.

## Boundaries

- The policy does not own SwiftUI `@Published` state, profile selection,
  connection-test generation counters, or async stale-result gates; those remain
  in `ProviderProfilesViewModel`.
- The policy does not read or write provider JSON files directly. It returns a
  save plan and lets the ViewModel call `ProviderProfileStore`.
- The policy does not own Keychain implementation details. It only consumes the
  `SecretStore` protocol and a minimal secret resolver closure.
- Provider adapter request/response behavior belongs to `KnowTypeProviders`.

## Behavior Notes

- Remote cloud providers that require keys must either receive a non-blank draft
  API key or reuse an existing secret for the same provider kind and endpoint
  credential scope.
- Blank draft API keys never cross provider kind or endpoint boundaries during
  save or connection test.
- A non-blank API key always receives a fresh
  `knowtype.provider.<profileID>.credential.<UUID>` reference. Legacy references
  remain reusable for unchanged profiles until their next secret change.
- Local OpenAI-compatible endpoints may keep an optional saved key only when the
  referenced secret still resolves and the provider kind plus credential scope
  match.
- Custom HTTP secrets are optional; unauthenticated custom HTTP profiles keep no
  `secretName`.
- At least one provider must remain default. Save-plan construction keeps only
  the saved profile marked default when the draft is default.

## Tests

- `ProviderProfileEditingPolicyTests`
- `ProviderProfilesViewModelTests`
