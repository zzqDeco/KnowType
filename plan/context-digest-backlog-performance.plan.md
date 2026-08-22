# Context Digest Backlog Performance

Status: Absorbed

## Current Record

The backlog-performance work is absorbed by the current Context Digest
contracts in `doc/architecture.plan.md`, `doc/interfaces.plan.md`, and
`plan/ai-request-amplification-control.plan.md`.

- Pending JSONL is capped at 500 events or 1 MiB and compacts to the newest 450
  events within 768 KiB. Text fields remain bounded to 2,048 Unicode scalars.
- One digest claims the oldest prefix of at most 50 events and 48 KiB. Appended
  tail bytes remain pending, and blank, malformed, oversized, or protected-only
  prefixes are archived locally without provider amplification.
- Recommendation and digest share one provider-identity gate. Ordinary provider
  failure uses a 60-second exponential cooldown, capped at 15 minutes; 429
  `Retry-After` remains clamped to 15 seconds through 15 minutes.
- The 600-second interval applies only after a successful provider ENV plus
  archive commit. Batch size cannot bypass it, and protected-only local archive
  does not start or advance it.
- One actor-owned deadline task handles first-pending eligibility, successful
  interval drain, local-archive tail drain, provider cooldown, and gate
  availability without polling or repeated snapshot decoding.
- Claim, receipt, and schedule recovery persist only privacy-safe hashes,
  timestamps, counts, and deadlines. Mismatched or corrupt evidence remains
  fail-closed without repeating provider work.

## Verification Boundary

The active Issue #212 plan owns focused regression coverage and macOS CI. Local
verification for this candidate remains limited to formatting and
`git diff --check`; build, test, performance, install, and application execution
run only in GitHub Actions.
