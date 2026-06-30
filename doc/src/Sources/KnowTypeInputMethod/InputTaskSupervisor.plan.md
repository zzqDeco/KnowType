# InputTaskSupervisor

`InputTaskSupervisor` is the small cancellation registry for input-method background work.

Current behavior:

- tracks replaceable tasks by `InputTaskKind`
- cancels stale work when a newer task supersedes the previous task of the same
  kind
- records cancellation counts for latency/debug diagnostics
- supervises only task kinds that still exist in the IMK product path, such as
  runtime lexicon reload and candidate-panel render work delegated by the panel
  publication runtime
- defines `InputLatencyTracer`, which emits stage timing only when `KNOWTYPE_INPUT_LATENCY_DEBUG=1`

It is intentionally independent of InputMethodKit. `InputControllerCoordinator` owns the policy for when
to replace tasks; the supervisor only centralizes cancellation and debug counters.
