# Persistent User Selection History

Goal: make local candidate learning survive input-method restarts without sending selection data to providers.

## Scope

- Persist selected prefix candidates under `~/Library/Application Support/KnowType/user-selection-history.json`.
- Keep `InputContext.userSelectionHistory` as the only ranking signal consumed by `CorrectionEngine`.
- Load history when the IMK controller starts and pass snapshots into immediate local suggestions and async provider-backed suggestions.
- Save history after prefix commits from Space, Tab, native candidate selection, and visible numeric candidate shortcuts.
- Serialize persistence writes on a shared queue and append only newly selected prefixes to the latest on-disk history so live input controllers do not overwrite each other's selections.
- Wait for pending writes when the IMK controller deactivates or closes.
- Keep failures non-blocking: missing, unreadable, or unwritable history must not break typing.

## Non-Goals

- No cloud upload of selection history.
- No third-party dictionary import.
- No provider prompt changes.
- No cross-device sync.

## Validation

- `FileUserSelectionHistoryStore` unit tests cover missing files, JSON round-trip, trim/cap behavior, legacy array loading, and zero-entry caps.
- Existing `CorrectionEngine` and `InputSessionController` tests continue to verify that history only reorders generated local candidates and remains a local context field.
