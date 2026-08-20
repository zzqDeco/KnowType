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
  60-second exponential failure cooldown, and bounded 0600 privacy-safe state
  under the default `~/.knowtype` directory; local budget and cancellation do
  not create provider failure state. A single-flight attempt owner records a
  timeout once, cancellation-marked late errors do not increment it again, and
  failure count clamps at 16 across memory and restart.
- Recommendation is `idle`, `debouncing`, `inFlight`, or `trailing`. Debounce is
  450 ms, new input replaces debounce work, and started transport keeps running
  while only the latest trailing revision may dispatch. Caller hard timeout is
  outside the shared gate, so cancellation-resistant transport retains its
  identity lease until actual completion and late success does not erase the
  timeout cooldown.
- Digest uses one actor-owned deadline task. A successful commit starts the
  600-second interval; batch, cooldown, and interval wakeups cannot bypass it.
  A below-batch first pending event gets a forced deadline, and gate busy uses
  one cancellable availability waiter rather than polling or repeated snapshot
  decode. Locally archived invalid prefixes rearm the unique deadline for any
  tail. Each claim is one precise prefix of at most 50 events and 48 KiB.
  Protected-only local archive does not start the 600-second provider-success
  interval. Corrupt schedule state imposes a fresh minimum-interval delay or
  remains fail-closed.
- ENV success is paired with a privacy-safe claim before archive. Recovery
  archives only the claimed prefix, keeps appended tail events pending, and
  avoids repeating the provider call. A durable archive receipt or bounded
  byte-count plus SHA-256 verification of the deterministic processed archive,
  together with timestamp/count schedule state, completes cleanup recovery
  across runtime or process rebuild. Corrupt evidence remains fail-closed. A
  claim saved before ENV replacement remains blocked while its generated hash
  is absent from ENV, without persisting provider output or redispatching.

## Verification Boundary

Focused regression suites and the full macOS CI job cover the source changes.
This candidate intentionally performs no local build, test, install, application,
or performance execution. The allowed local check is `git diff --check` only;
GitHub Actions must run full `swift test`, install smoke coverage, and
`./scripts/perf-input-hotpath.sh`.
