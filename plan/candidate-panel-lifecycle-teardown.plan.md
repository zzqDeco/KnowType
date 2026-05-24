# Candidate Panel Lifecycle Teardown

Status: Active

## Summary

Fix stale candidate-panel windows after rapid Space/Return, input-source switches, host deactivation, or controller close.

KnowType keeps its candidate panel as a non-activating high-level `NSPanel` with `hidesOnDeactivate = false`, so the coordinator must explicitly hide it. This matches mature IMK input methods: Squirrel hides palettes on deactivate and commit, Mozc sends renderer `visible=false`, and McBopomofo drives its candidate controller to `visible=false` from deactivated/empty states.

## Implementation

- Add a shared composition lifecycle teardown path for commit, deactivate, close, reset, and native-ended cases.
- Hide the panel and invalidate panel render, delayed reanchor, local suggestion, and AI recommendation work before clearing composition state.
- Pass the current IMK client into `deactivateServer(client:)`, falling back to the current host client when IMK sends a non-client callback sender; deactivate commits the active raw composition through the normal insert path when needed, but does not call `setMarkedText("")`.
- Require active raw/native preedit before publishing candidate-panel updates, so stale suggestions or delayed reanchors cannot show the panel after composition ends.
- Treat native handled/no-commit results with empty raw/preedit as ended composition, clear stale marked text, and run teardown instead of publishing candidates.

## Validation

- `swift test --quiet`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`

Manual acceptance: install release KnowType and verify rapid `wo` + Space/Return in TextEdit, Chrome, and Spotlight never leaves a floating candidate panel behind.
