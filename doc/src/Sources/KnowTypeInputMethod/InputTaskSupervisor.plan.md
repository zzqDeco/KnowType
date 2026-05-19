# InputTaskSupervisor

`InputTaskSupervisor` is the small cancellation registry for input-method background work.

Current behavior:

- tracks replaceable tasks by `InputTaskKind`
- cancels stale work when a newer raw-input generation supersedes it
- records cancellation counts for latency/debug diagnostics
- defines `InputGeneration` as the value used to reject stale asynchronous publications
- defines `InputLatencyTracer`, which emits stage timing only when `KNOWTYPE_INPUT_LATENCY_DEBUG=1`

It is intentionally independent of InputMethodKit. `InputControllerCoordinator` owns the policy for when
to replace tasks; the supervisor only centralizes cancellation and debug counters.
