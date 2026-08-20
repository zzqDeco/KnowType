# AI Request Amplification Control

Status: Active

## Objective

Bound the four amplification paths in Issue #212: recursive `ENV.md` context,
Context Digest batch bypass of `minimumInterval`, cancellation and re-dispatch
of already-started recommendations, and independent provider failure budgets.

## Current Contract

- `ENV.md` is canonicalized to one managed generated marker pair and one User
  Notes section. A digest accepts exactly one markdown candidate, at most 4 KiB
  and 200 lines, without KnowType markers, document titles, User Notes titles,
  multiple candidates, or empty content.
- Legacy migration is bounded to 1 MiB, content-hash deduplicates 0600 backups,
  treats markerless files as user content, restores known recursive pollution,
  and fails closed on ambiguity. Backup and claim files never enter provider
  context.
- Recommendation and digest have explicit UTF-8 logical and HTTP budgets.
  Over-limit local input is skipped without provider-failure accounting; cache
  fingerprints are computed from the budgeted payload.
- One hashed `ProviderRequestGate` is shared by recommendation and digest.
  Each identity has one in-flight request, generation fencing, bounded 429 or
  exponential cooldown, and privacy-safe state.
- Recommendation is `idle`, `debouncing`, `inFlight`, or `trailing`. Debounce is
  450 ms, new input replaces debounce work, and started transport keeps running
  while only the latest trailing revision may dispatch.
- Digest uses one actor-owned deadline task. A successful commit starts the
  600-second interval; batch, cooldown, and interval wakeups cannot bypass it.
  Each claim is one precise prefix of at most 50 events and 48 KiB.
- ENV success is paired with a privacy-safe claim before archive. Recovery
  archives only the claimed prefix, keeps appended tail events pending, and
  avoids repeating the provider call.

## Verification Boundary

Focused regression suites and the full macOS CI job cover the source changes.
This candidate intentionally performs no local build, test, install, application,
or performance execution. The allowed local check is `git diff --check` only;
GitHub Actions must run full `swift test`, install smoke coverage, and
`./scripts/perf-input-hotpath.sh`.
