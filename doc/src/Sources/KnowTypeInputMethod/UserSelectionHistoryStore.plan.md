# UserSelectionHistoryStore

`UserSelectionHistoryStore` owns local persistence for prefix candidate choices made in the macOS input-method frontend.

Responsibilities:

- store only selected prefix candidate text, not raw protected input or provider responses
- keep history under `~/Library/Application Support/KnowType/user-selection-history.json`
- expose a no-create default-store mode for IMK cold start; startup can compute
  the canonical path and load existing history without creating the `KnowType`
  directory
- trim whitespace, drop empty selections, and cap history before writing
- load missing history as an empty list
- support a legacy JSON array shape so early MVP builds can migrate without user action

The store is intentionally in `KnowTypeInputMethod` instead of `KnowTypeCore`: core ranking consumes a plain `InputContext.userSelectionHistory` snapshot, while host storage remains an input-method concern.

Persistence failure is non-fatal. The IMK controller keeps the in-memory history for the active process and silently degrades when the file cannot be read or written.

The first real selection write may create the storage directory. Opening the
store or loading a missing history file during controller initialization must
remain read-only, so system prelaunch does not mutate user data.

`UserSelectionHistoryPersistence` serializes writes through a shared process-wide queue. Each record operation keeps the active controller's in-memory history responsive, then appends only the newly selected prefix to the latest on-disk history on the persistence queue. Flush waits for queued writes instead of re-saving a stale controller snapshot, so a long-lived controller cannot push newer selections from another host app out of the capped history.
