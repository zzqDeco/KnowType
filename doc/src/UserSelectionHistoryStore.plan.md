# UserSelectionHistoryStore

`UserSelectionHistoryStore` owns local persistence for prefix candidate choices made in the macOS input-method frontend.

Responsibilities:

- store only selected prefix candidate text, not raw protected input or provider responses
- keep history under `~/Library/Application Support/KnowType/user-selection-history.json`
- trim whitespace, drop empty selections, and cap history before writing
- load missing history as an empty list
- support a legacy JSON array shape so early MVP builds can migrate without user action

The store is intentionally in `KnowTypeInputMethod` instead of `KnowTypeCore`: core ranking consumes a plain `InputContext.userSelectionHistory` snapshot, while host storage remains an input-method concern.

Persistence failure is non-fatal. The IMK controller keeps the in-memory history for the active process and silently degrades when the file cannot be read or written.

`UserSelectionHistoryPersistence` serializes writes through a shared process-wide queue. Each record operation keeps the active controller's in-memory history responsive, then appends only the newly selected prefix to the latest on-disk history on the persistence queue. Flush waits for queued writes instead of re-saving a stale controller snapshot, so a long-lived controller cannot push newer selections from another host app out of the capped history.
