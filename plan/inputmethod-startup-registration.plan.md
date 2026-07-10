# Input Method Startup Registration

## Summary

Normal `KnowTypeInputMethodApp` launch must create its `IMKServer` and service input immediately, even when macOS never exposes the registered parent or visible mode. Registration, enablement, selection, and bounded waits remain explicit installer or repair operations.

## Scope

- Make the ordinary input-method host path serve-only.
- Keep all existing activation flags, source identifiers, canonical bundle registration, and wait behavior on explicit command-line paths.
- Add a small startup policy in `KnowTypeInputSourceSupport` so tests can inject a never-visible registration path without sleeping.
- Add a source guard for the `applicationDidFinishLaunching` boundary.
- Do not change installer scripts, bundle metadata, source identifiers, or root README installer guidance.

## Implementation

- `TextInputSourceActivation` identifies its explicit command flags before application startup.
- `KnowTypeInputMethodStartupPolicy.run` executes either the normal server path or the explicit command path, never both.
- `KnowTypeAppDelegate.applicationDidFinishLaunching` only resolves bundle metadata, creates `IMKServer`, and logs launch metadata.
- Existing `TISRegisterInputSource`, enable/select calls, and parent/mode waits remain inside `TextInputSourceActivation.handleCommandLineActivation`.
- No startup self-repair or background diagnostics are added in this slice.

## Test Plan

- `InputMethodHostStartupPolicyTests`: simulate parent and mode records that never become visible and verify serve-only startup does not invoke either wait; verify explicit command execution still owns the wait path.
- `KnowTypeInputSourceSupportTests`: retain shared TIS and LaunchServices helper coverage.
- `InputMethodBundleInfoTests`: guard the delegate against registration, enablement, selection, waits, and sleeps while preserving explicit activation source calls.
- `./scripts/smoke-inputmethod-install.sh`: retain deterministic install and bundle contract coverage.
- Full gates: `swift test` and `git diff --check`.

## Assumptions

- AppKit begins normal event servicing through `NSApplication.run`; the delegate performs no work after creating the server and writing the launch log.
- Registration repair remains an explicit operational action rather than automatic host self-repair.
- A real installed cold-start remains a manual acceptance step because the repository smoke does not mutate the developer's active Text Input Source state.
