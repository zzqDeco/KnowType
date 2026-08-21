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
  failure count clamps at 16 across memory and restart. The gate issues a
  non-reusable attempt id and persists timeout failure before that attempt's
  caller-visible timeout can expose lease availability. With persistence
  enabled, permission, read, decode, encode, atomic-write, replace, or final
  chmod failure blocks new attempts and cannot be cleared by generation
  invalidation. A value-only preflight exposes that state before recommendation
  document projection or digest snapshot decoding; each runtime then latches it
  without repeated admission work. Cancellation between attempt admission and
  transport registration aborts the matching attempt without cooldown and
  wakes waiters. Timeout ownership before transport atomically records cooldown,
  releases the matching attempt, completes its callback, and fences the late
  operation task before provider invocation. Once transport starts, timeout
  records once and only the real fenced completion releases its lease. The gate
  actor binds each active id and generation to that same phase fence and
  exactly-once completion. Generation invalidation aborts an admitted attempt
  without cooldown and permits immediate new-generation admission, while a
  started transport remains busy until its stale-fenced real completion. The
  registry assigns one explicit target generation before crossing to the gate;
  concurrent lease and revision paths coalesce behind that actor-owned
  transition until gate linearization, capability reset, and generation
  publication complete exactly once.
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
  remains fail-closed, including impossible date ordering and excessive future
  deadlines; a positive pending count with all three time anchors absent is
  also repaired conservatively. Calls received while a digest is active
  coalesce into one immediate post-completion re-evaluation, unless a busy-gate
  availability waiter already owns the single wake for that contention episode.
  When a record, manual, or deadline wake reaches an active live-claim guard,
  one signal remains latched until the actor flow and real gate attempt both
  finish. If pending events remain, one actor-owned full re-evaluation then
  reapplies interval, cooldown, gate, and generation checks; no blocked wake
  produces no late-completion rerun.
- ENV success is paired with a privacy-safe claim before archive. Recovery
  archives only the claimed prefix, keeps appended tail events pending, and
  avoids repeating the provider call. A durable archive receipt or bounded
  byte-count plus SHA-256 verification of the deterministic processed archive,
  together with timestamp/count schedule state, completes cleanup recovery
  across runtime or process rebuild. Corrupt evidence remains fail-closed. A
  claim saved before ENV replacement remains blocked while its generated hash
  is absent from ENV, without persisting provider output or redispatching. A
  restarted runtime performs this local recovery before its first append can
  compact pending data. A blocked recovery uses one bounded 60-second actor
  deadline; records during backoff do not repeat recovery reads or append, and
  each deadline permits one retry. Initial recovery installs an actor-owned
  single-flight token before any cross-actor await, so concurrent records and
  process calls share one result and only the current owner can update cleanup,
  latch, or retry state. ENV permissions are restricted before reads, structural
  User Notes must follow the unique managed pair, and existing hash-named
  backups are verified as matching regular non-symlink files. Registry-backed
  claim creation begins inside the final synchronous current-lease guard, so a
  stale result cannot leave a pre-ENV orphan claim. Valid processed-archive
  evidence clears only missing or provably different pending data, archives an
  exact prefix, and blocks truncated or unreadable pending state. An in-memory
  active prefix remains protected through compaction until both the digest flow
  and any cancellation-resistant gate attempt have actually finished.

## Verification Boundary

Focused regression suites and the full macOS CI job cover the source changes.
This candidate intentionally performs no local build, test, install, application,
or performance execution. The allowed local check is `git diff --check` only;
GitHub Actions must run full `swift test`, install smoke coverage, and
`./scripts/perf-input-hotpath.sh`.
