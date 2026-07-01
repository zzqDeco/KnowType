# Candidate Panel Lifecycle Teardown

Status: Active

## Summary

Fix stale candidate-panel windows after rapid Space/Return, input-source switches, host deactivation, or controller close.

KnowType keeps its candidate panel as a non-activating high-level `NSPanel` with `hidesOnDeactivate = false`, so the coordinator must explicitly hide it. This matches mature IMK input methods: Squirrel hides palettes on deactivate and commit, Mozc sends renderer `visible=false`, and McBopomofo drives its candidate controller to `visible=false` from deactivated/empty states.

Current root cause: candidate-panel publication has stale gates inside `InputCandidatePanelPublicationRuntime`, but the host/AppKit seam previously split publication into unordered `updateCandidatePanel(state:)` and `hideCandidatePanel()` calls and dropped `CandidatePanelFrame` metadata. A fast `d` + Space could therefore send a newer hide to the window, then replay an older visible frame with the pre-commit candidates and order the panel front again.

## Implementation

- Add a shared composition lifecycle teardown path for commit, deactivate, close, reset, and native-ended cases.
- Hide the panel and invalidate panel render, delayed reanchor, local suggestion, and AI recommendation work before clearing composition state.
- Pass the current IMK client into `deactivateServer(client:)`, falling back to the current host client when IMK sends a non-client callback sender; deactivate commits the active raw composition through the normal insert path when needed, but does not call `setMarkedText("")`.
- Require active raw/native preedit before publishing candidate-panel updates, so stale suggestions or delayed reanchors cannot show the panel after composition ends.
- Treat native handled/no-commit results with empty raw/preedit as ended composition, clear stale marked text, and run teardown instead of publishing candidates.
- Keep the AppKit window cache consistent with visibility: hidden state, layout failure, deactivate/close/reset/commit teardown, and screen-geometry changes must clear or bypass the presentation fast path before any future `orderFrontRegardless()`.
- Use a single ordered candidate-panel frame channel across `InputControllerHost`; visible, hidden, stale-update, and layout-impossible frames all carry a monotonic `presentationGeneration`.
- Treat `InputCandidatePanelPublicationRuntime` as the only presentation-generation owner, while `CandidatePanelWindowController` only rejects stale frames older than the latest applied generation.
- Lock the fast `d` + Space regression with coordinator tests and window tests: `visible(gen: 1)` followed by `hidden(gen: 2)` must not be reopened by replayed `visible(gen: 1)`.

## Validation

- `swift test --quiet`
- `./scripts/smoke-inputmethod-install.sh`
- `./scripts/perf-input-hotpath.sh`
- `git diff --check`

Manual acceptance: install release KnowType and verify rapid `d` + Space, `wo` + Space/Return, and `nihao` + Space/Escape in TextEdit, Chrome, Codex, and Spotlight never leaves or reopens a stale floating candidate panel.
