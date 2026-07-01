# MVP Test Acceptance Matrix

This matrix explains what each MVP verification layer proves today, what it
does not prove, and where follow-up test work should land. It is intentionally
current-state focused: rows describe the coverage currently present on `dev`.

## Gates

| Gate | Current status | Guarantees | Does not prove | Evidence to record |
|---|---|---|---|---|
| `swift test` | Required PR gate in CI and before local IME acceptance | Product logic for correction, prefix-locked continuation, Level 0 no-provider routing, technical-token preservation, candidate list state, shortcut mapping, provider adapter request/response normalization through mock HTTP clients, provider profile persistence, settings ViewModel behavior, bundle metadata, and script source invariants | Real `IMKInputController` lifecycle, host app marked-text behavior, visible candidate window placement, local install and TIS selection, Gatekeeper policy acceptance, live provider availability, or SwiftUI rendered layout | Command, platform, commit SHA, and failed test names if any |
| CI script smoke | Runs on macOS CI after `swift build` and `swift test` | Shell syntax for all current input-method workflow scripts, read-only help paths for diagnose/select/profile generation, `scripts/build-inputmethod-bundle.sh`, Developer Preview DMG packaging helpers, bundle contents, ad-hoc signing smoke, and local SystemPolicyRule mobileconfig payload shape | Mutating install/select/uninstall behavior, `TextInputMenuAgent` cache state, active input-source state in a frontmost app, or typing behavior | CI run URL and the exact workflow job |
| Env-gated provider live smoke | Present and skipped by default unless `KNOWTYPE_PROVIDER_LIVE_SMOKE=1` is set | When enabled, proves a configured OpenAI-compatible endpoint such as `http://127.0.0.1:8317/v1` can complete `/v1/models` discovery and can complete a continuation request with an explicit product-style model; model discovery skips obvious non-chat models such as image and embedding IDs | Default CI provider health, remote provider correctness without credentials, every adapter's production SLA, or that the first `/v1/models` completion-capable model is fast enough for KnowType | Environment variable names, endpoint class, discovered model, effective continuation model, command, and sanitized response summary |
| Manual local IME acceptance | Required before claiming local IME behavior | Installed Apple Development bundle can be allowed by macOS policy, registered, enabled, selected in the target app, and used for real typing in TextEdit, Safari/Chrome, Electron-style text fields, Terminal, Xcode, and chat inputs from `doc/mvp-acceptance.plan.md`; `scripts/accept-inputmethod-local.sh` generates the report template | Reproducible CI proof, universal compatibility with every host app, notarized distribution behavior, or long-run stability | macOS version, signing identity class, build commit, commands run, active app names/versions, typed probes, screenshots or screen recording, and relevant KnowType/Gatekeeper logs |

## Coverage Gaps From Issue #61

| Gap | Current interpretation | Future work |
|---|---|---|
| `InputController.swift` direct IMKit coverage | `swift test` covers session and composition logic around it, but not the actual IMK lifecycle, client read/write calls, delayed re-anchor, reset, deactivate, or host-client forwarding | `test/input-controller-host-seams` should add a testable host/client seam and cover marked text, commit, reset, deactivate, and candidate refresh behavior |
| `CandidatePanelWindowController.swift` window behavior | Placement, sizing, window-operation, and content-rendering seams now cover anchor movement, screen-edge avoidance, invalid-anchor hiding, and size constraints; real `NSPanel` rendering still needs local acceptance | Mouse selection callbacks and rendered AppKit behavior should be covered in a later focused PR if the row model exposes selection identity cleanly |
| Install, selection, and macOS policy chain | CI validates script syntax, bundle construction, ad-hoc signing smoke, and local SystemPolicyRule profile payload shape without mutating runner Text Input Source state | Local diagnostics and manual typing acceptance are still required for real profile installation, TIS selection, and host app behavior |
| Real host app behavior | Manual probes are the source of truth for TextEdit, browser, Electron, Terminal, Xcode, WeChat, and Feishu behavior | Host-specific failures should become narrow `fix/*` branches while shared IMK behavior should be covered through the controller and panel seams |
| Provider live behavior | Adapter fixtures prove mapping and parsing without network calls; env-gated live smoke can exercise local OpenAI-compatible discovery and continuation when explicitly enabled | Live smoke does not run in normal CI and does not prove every provider or endpoint configuration |
| Chinese candidate quality | Regression corpus covers common compact pinyin, one-syllable candidate breadth, partial pinyin, abbreviations, ranking, persistence-adjacent behavior, and lexicon-size boundaries | Broader real-world quality still depends on larger licensed dictionaries and local acceptance with user typing probes |
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
