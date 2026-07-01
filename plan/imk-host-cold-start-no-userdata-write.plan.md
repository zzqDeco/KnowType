# KnowType IMK Host Cold Start No User Data Write

## Summary

- Status: Active.
- Branch: `fix/imk-host-cold-start-no-userdata-write`.
- Goal: macOS may prelaunch `KnowTypeInputMethodApp` during TIS or
  LaunchServices work, but that cold start must not initialize Rime, provider
  profiles, selection history, AI learning files, lexical profiles, `ENV.md`,
  or `CORRECTION.md`.
- The fix aligns KnowType with mature IMK apps: install/register and host
  startup are separate from the first real input session.

## Scope

- Make `RimeConversionEngine` hold configuration on init and create the native
  Rime session only on the first real conversion `process(_:)` call.
- Make provider-backed AI recommendation and context memory runtime lazy from
  `KnowTypeInputController` startup.
- Keep accepted AI learning, feedback learning, and lexical profile stores
  read-only on construction; explicit record/rebuild/refresh paths still write.
- Open user selection history in no-create mode on controller startup; the first
  real candidate-selection write may create the store.
- Change install postflight to use the JSON install snapshot rather than full
  `--strict` TIS diagnostics.

## Implementation

- `RimeConversionEngine.snapshot`, `activeSchemaID`, `isNativeActive`, and
  `reset()` are cold-start read-only operations and must not create Rime
  user/log directories.
- `NativeRimeSession` creation remains unchanged once reached. Engine
  construction and read-only access still do not create a session; later
  first-key performance work may explicitly prewarm a temporary native session
  after `KnowTypeInputController` is live, but install/register scripts and
  read-only diagnostics still do not perform that prewarm.
- `ProviderRuntimeLoader.loadDefaultProvider(createProfileDirectory: false)`
  opens the default provider path without creating `Application Support/KnowType`
  when no provider profile exists.
- `LazyDefaultAIRecommendationRuntime` and `LazyDefaultAIContextMemoryRuntime`
  defer provider loading and AI document-store construction until a real
  recommendation or typing event is processed.
- The coordinator distinguishes a known eager provider from a lazy AI runtime
  wrapper. A lazy wrapper can schedule cloud AI, but it does not suppress the
  no-provider local continuation fallback until a real provider is known. The
  lazy recommendation runtime publishes provider availability only after its
  loader has actually resolved available/unavailable.
- Accepted learning and feedback startup reads take the existing maintenance
  file lock when one is already present, but they do not create lock files or
  parent directories merely to inspect missing history.
- Install postflight treats a successful JSON diagnostic process with non-empty
  `failures` as a warning rather than reporting a clean postflight.
- `KNOWTYPE_STARTUP_DEBUG=1` logs lazy cold-start state without user text.

## Test Plan

- `RimeConversionEngine()` init/read/reset do not create configured Rime
  user/log directories; first `process(.text("n"))` does.
- Provider profile no-create loading returns an empty profile file without
  creating the `KnowType` directory.
- User selection history no-create loading returns the expected file path
  without creating the `KnowType` directory; save still creates it.
- Lazy AI recommendation runtime presence does not suppress local fallback
  continuations until provider availability is known, and suppresses stale local
  fallback rows after a lazy provider has loaded.
- Accepted learning, feedback learning, and lexical profile stores do not create
  missing directories or lock files on init/snapshot.
- `install-inputmethod.sh` postflight calls `diagnose-inputmethod.sh --json`
  instead of full `--strict` and parses the JSON `failures` array.
- Regression: `swift test --quiet`,
  `./scripts/smoke-inputmethod-install.sh`,
  `./scripts/smoke-inputmethod-install.sh --with-prefpane`,
  `./scripts/perf-input-hotpath.sh`, and `git diff --check`.

## Assumptions

- First real user input, or a post-controller-init explicit Rime prewarm in the
  performance path, may initialize Rime runtime directories as normal product
  behavior.
- This slice did not change candidate UI, provider prompts, Rime dictionaries,
  or release packaging. Later input-source work may change the registration
  model without changing the cold-start user-data boundary.
- Helper-selection failures remain a separate follow-up if they still appear
  after input-source registration fixes.
