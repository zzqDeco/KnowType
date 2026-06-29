# InputSelectionHistoryRuntime

## Responsibility

`InputSelectionHistoryRuntime` owns the input-method session boundary for local
prefix-selection learning.

It trims selected candidate text, applies `TextProtection` guards to the selected
text and raw input, publishes the `candidateSelected` runtime event payload, keeps
the in-process recent selection cache used by lexical profile refresh, and routes
accepted selections to `InputControllerUserSelectionHistoryPersisting`.

## Boundaries

- File format, directory creation, merge-with-disk behavior, and serial write
  ordering stay in `UserSelectionHistoryStore` and `UserSelectionHistoryPersistence`.
- Rime candidate selection, candidate-panel ordering, commit policy, and host
  marked-text writes stay in `InputControllerCoordinator` and adjacent input
  runtimes.
- Provider adapters must never receive the full selection log. They can receive
  only bounded lexical summaries produced by the AI lexical profile layer.

## Behavior Notes

- The runtime keeps persisted history separate from `recentSelectionHistory`.
  Existing disk history is loaded for local learning persistence, but it is not
  injected wholesale into the AI lexical context for a fresh IMK process.
- Protected selections and protected raw input are skipped before event
  publication, recent-cache updates, or persistence writes.
- `flush()` delegates to the persistence boundary so controller lifecycle hooks
  do not know the storage shape.

## Tests

- `InputSelectionHistoryRuntimeTests`
- `InputControllerCoordinatorTests`
- `swift test`
