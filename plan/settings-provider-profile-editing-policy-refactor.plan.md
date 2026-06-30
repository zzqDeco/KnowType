# Settings Provider Profile Editing Policy Refactor

Status: Active

## Summary

Extract provider profile draft validation, save planning, secret mutation, and
connection-test configuration from `ProviderProfilesViewModel` into
`ProviderProfileEditingPolicy`.

This is a pure refactor. Settings UI layout, provider JSON schema, Keychain
behavior, connection-test semantics, default templates, and runtime provider
loading stay unchanged.

## Scope

- Add `ProviderProfileEditingPolicy` under `KnowTypeSettingsUI`.
- Keep `ProviderProfilesViewModel` responsible for `@Published` state, profile
  selection, persistence sequencing, connection-test generation, and stale-result
  gating.
- Move validation, default-provider save-only validation, profile-scoped secret
  names, secret reuse decisions, save-plan construction, transient connection
  configuration, and secret mutation application into the policy.
- Add focused policy tests while keeping ViewModel behavior tests as regression
  coverage.
- Update source notes and indexes for the new Settings UI boundary.

## Non-Goals

- Do not change SwiftUI layout, localized copy, provider file schema, Keychain
  implementation, provider adapters, runtime loader, default provider templates,
  or input-method behavior.
- Do not add settings UI for new provider policies.
- Do not run install, repair, or input-method scripts.

## Validation

- `swift test --quiet --filter ProviderProfileEditingPolicyTests`
- `swift test --quiet --filter ProviderProfilesViewModelTests`
- `swift test --quiet --filter ProviderProfilesPresentationTests`
- `swift test --quiet --filter ProviderProfileTests`
- `swift test`
- `git diff --check`

## Assumptions

- `ProviderProfileDraft` keeps its public shape so SwiftUI bindings and existing
  tests remain stable.
- `ProviderProfilesViewModelError` messages remain the user-facing error source
  for missing API keys and rollback failures.
- Secret reuse continues to require the same provider kind and endpoint
  credential scope.
