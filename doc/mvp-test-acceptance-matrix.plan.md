# MVP Test Acceptance Matrix

This matrix explains what each MVP verification layer proves today, what it
does not prove, and where follow-up test work should land. It is intentionally
current-state focused: planned rows name expected branches without claiming the
coverage already exists.

## Gates

| Gate | Current status | Guarantees | Does not prove | Evidence to record |
|---|---|---|---|---|
| `swift test` | Required PR gate in CI and before local IME acceptance | Product logic for correction, prefix-locked continuation, Level 0 no-provider routing, technical-token preservation, candidate list state, shortcut mapping, provider adapter request/response normalization through mock HTTP clients, provider profile persistence, settings ViewModel behavior, bundle metadata, and script source invariants | Real `IMKInputController` lifecycle, host app marked-text behavior, visible candidate window placement, local install and TIS selection, Gatekeeper policy acceptance, live provider availability, or SwiftUI rendered layout | Command, platform, commit SHA, and failed test names if any |
| CI script smoke | Runs on macOS CI after `swift build` and `swift test` | Shell syntax for the current input-method workflow scripts, read-only help paths for diagnose/select, `scripts/build-inputmethod-bundle.sh`, and bundle contents: executable, `Info.plist`, SwiftPM core resource bundle, and input-source icon | Mutating install/select/uninstall behavior, local SystemPolicyRule profile payload, `TextInputMenuAgent` cache state, active input-source state in a frontmost app, or typing behavior | CI run URL and the exact workflow job |
| Env-gated provider live smoke | Planned; should default to skipped unless explicit provider environment is set | When enabled, should prove a configured OpenAI-compatible endpoint such as `http://127.0.0.1:8317/v1` can complete `/v1/models` discovery and a continuation request, and that provider failures degrade without blocking traditional candidates | Default CI provider health, remote provider correctness without credentials, or every adapter's production SLA | Environment variable names, endpoint class, model, command, and sanitized response summary |
| Manual local IME acceptance | Required before claiming local IME behavior | Installed Apple Development bundle can be allowed by macOS policy, registered, enabled, selected in the target app, and used for real typing in TextEdit, Safari/Chrome, Electron-style text fields, Terminal, Xcode, and chat inputs from `doc/mvp-acceptance.plan.md` | Reproducible CI proof, universal compatibility with every host app, notarized distribution behavior, or long-run stability | macOS version, signing identity class, build commit, commands run, active app names/versions, typed probes, screenshots or screen recording, and relevant KnowType/Gatekeeper logs |

## Coverage Gaps From Issue #61

| Gap | Current interpretation | Future work |
|---|---|---|
| `InputController.swift` direct IMKit coverage | `swift test` covers session and composition logic around it, but not the actual IMK lifecycle, client read/write calls, delayed re-anchor, reset, deactivate, or host-client forwarding | `test/input-controller-host-seams` should add a testable host/client seam and cover marked text, commit, reset, deactivate, and candidate refresh behavior |
| `CandidatePanelWindowController.swift` window behavior | Renderer and state tests prove row construction and selection state, but not `NSPanel` creation, screen-edge avoidance, anchor movement, mouse selection, or stale-frame avoidance | `test/candidate-panel-window-geometry` should add a window/screen seam or AppKit smoke tests for panel geometry and interaction |
| Install, selection, and macOS policy chain | CI currently avoids mutating runner Text Input Source state; local diagnostics are necessary before typing acceptance | `test/install-profile-script-smoke` should extend CI smoke to `scripts/create-local-system-policy-profile.sh`, `scripts/lib/inputsource-tool.sh`, and profile payload fields |
| Real host app behavior | Manual probes are the source of truth for TextEdit, browser, Electron, Terminal, Xcode, WeChat, and Feishu behavior | Host-specific failures should become narrow `fix/*` branches while shared IMK behavior should be covered through the controller and panel seams |
| Provider live behavior | Adapter fixtures prove mapping and parsing without network calls; settings diagnostics can test a configured endpoint locally | `test/provider-live-smoke` should add an env-gated test target or script that is skipped by default and never requires secrets in normal CI |
| Chinese candidate quality | Existing unit tests cover important pinyin, compact pinyin, partial pinyin, seed lexicon, runtime lexicon, and user-selection ranking paths | `test/chinese-regression-corpus` should add an extensible corpus for common compact pinyin, one-syllable pagination, partial pinyin, abbreviations, ranking, persistence, and lexicon-size boundaries |
| SwiftUI view rendering | ViewModels are tested, but `ProviderProfilesView.swift` and other SwiftUI layouts are not directly snapshot- or inspection-tested | Future settings UI work should either add view inspection/snapshot coverage or keep moving logic into tested ViewModels |

## Computer Use And Local App Verification

Computer Use or another local automation tool can help drive target apps,
capture screenshots, and make manual acceptance easier to repeat. Treat that
evidence as local manual verification, not CI proof.

Local app verification depends on mutable machine state: installed profiles,
Gatekeeper assessment, signing identity, Text Input Source caches, frontmost app
selection context, host app version, and accessibility permissions. A passing
Computer Use run can support an acceptance note only when it records the same
evidence expected from manual local IME acceptance. It must not be summarized as
"CI passed" unless the corresponding CI workflow actually ran and passed.

## Release Claim Rule

MVP release notes may claim behavior only at the strongest gate that proved it.
For example, prefix-lock sanitization and Level 0 no-cloud behavior can cite
`swift test`; bundle packaging can cite CI script smoke; TextEdit or Chrome
candidate-window behavior must cite manual local IME acceptance until the
corresponding AppKit/IMKit seams are automated.
