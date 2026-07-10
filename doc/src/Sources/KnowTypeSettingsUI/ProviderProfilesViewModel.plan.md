# ProviderProfilesViewModel

`ProviderProfilesViewModel` is the settings-app state owner for provider profile editing.

## Responsibilities

- Load provider profiles from `ProviderProfileStore`, seeding default profiles when the store is empty.
- Use `KnowTypeProviders.ProviderProfileTemplates` so settings defaults match IMK runtime defaults.
- Delegate draft validation, save-plan construction, profile-scoped secret mutation, and transient connection-test configuration to `ProviderProfileEditingPolicy`.
- Test the current provider draft by asking the policy for a transient `ProviderConfiguration` and running `ProviderConnectionDiagnostic` without saving provider metadata.
- Commit profile updates through an expected-revision store transaction so a
  failed or stale mutation does not publish unsaved profile state.

## Persistence Notes

Load failures block settings persistence until profiles can be loaded
successfully. Before every save, default change, and connection test, the
ViewModel reloads and compares its baseline. A mismatch keeps the draft,
refreshes saved profiles, rejects the operation, and surfaces localized conflict
copy. Store compare-and-swap performs the same check again at commit time.
An unmigrated legacy profile file, a missing post-migration canonical file, or
an old Settings writer recreating `providers.json` is therefore never treated
as an empty profile list. The installer owns migration and conflict detection; the ViewModel
stays fail-closed and preserves the user's draft.

Changed secrets use immutable credential references. The ViewModel writes a new
secret before committing metadata, deletes that new secret if metadata commit
fails, and cleans an old unreferenced secret only after the metadata commit.
Cleanup failure leaves the valid new metadata/credential pair active and is
reported as a non-rollback persistence warning.

Connection tests use a non-blank draft API key only for the test request. Blank draft API keys reuse an existing saved secret only when the policy confirms the saved secret still belongs to the same provider kind and endpoint credential scope. Missing required keys fail before the diagnostic sends a provider request, and invalid draft fields refresh `validationErrors` before returning while preserving save-only errors such as the single-default-provider rule.

Connection status is scoped to the draft snapshot and provider-file revision
being tested. Editing draft fields or switching profiles resets stale connection
status. The ViewModel rechecks disk state before sending and before publishing an
in-flight result. A test that began immediately before another process commits
may finish its old request, but immutable references guarantee that E1 can only
carry K1; the stale result is then rejected instead of published. Diagnostic
failures remain separate from the persistent save/load error slot.

When a saved profile is edited to another provider protocol, another remote endpoint, or a local endpoint, a blank draft API key does not reuse the saved remote secret for the connection test. This mirrors save behavior for remote-to-local optional-secret transitions and prevents old cloud keys from being sent to a different provider.

`ProviderProfilesViewModel` remains the `@MainActor` UI state owner. It should not grow new provider credential policy helpers; add those rules to `ProviderProfileEditingPolicy` and keep the ViewModel limited to selection, persistence sequencing, connection-test generation, and result publication.
