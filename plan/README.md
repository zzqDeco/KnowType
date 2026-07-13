# KnowType Plan Index

`plan/` stores active implementation plans and short records for recently
delivered work. Current system behavior belongs in [doc/](../doc/README.md);
plans should stay implementation-oriented and retire once stable behavior is
absorbed into current-state documentation.

Use [the implementation plan template](templates/implementation-plan.template.md)
for new work and [the delivered plan template](templates/delivered-plan.template.md)
when converting a shipped plan into a short record.

## Status Definitions

- `Active`: work is still being designed, implemented, or used as a live
  decision source.
- `Delivered`: work has shipped, but the record is still useful for release
  notes, review context, or recent branch archaeology.
- `Absorbed`: stable behavior has moved into `doc/`; the plan can usually be
  removed in a docs cleanup.
- `Retire Candidate`: old or duplicated plan that should be deleted once links
  and docs are checked.

## Active References

| Document | Purpose | Status |
|---|---|---|
| [release-0.2.7.plan.md](release-0.2.7.plan.md) | Prepare and publish the KnowType v0.2.7 Developer Preview release | Active |
| [multi-api-v1.plan.md](multi-api-v1.plan.md) | Provider abstraction, protocol compatibility, correction, continuation, and workflow | Active |
| [chinese-engine-foundation.plan.md](chinese-engine-foundation.plan.md) | MVP Chinese input engine foundation and candidate behavior | Active |
| [chinese-lexicon-index.plan.md](chinese-lexicon-index.plan.md) | Larger-lexicon indexing path for `TraditionalInputEngine` | Active |
| [pr23-chinese-prefix-completions.plan.md](pr23-chinese-prefix-completions.plan.md) | Cleanup of useful Chinese prefix completion gaps from stale PR work | Active |
| [pinyin-cloud-fallback-policy.plan.md](pinyin-cloud-fallback-policy.plan.md) | Provider fallback policy for unknown pinyin-shaped input | Active |
| [privacy-app-rules-mvp.plan.md](privacy-app-rules-mvp.plan.md) | Level 0 no-provider routing and protected app rules | Active |
| [user-selection-ranking.plan.md](user-selection-ranking.plan.md) | Local ranking boost from recent prefix selections | Active |
| [persistent-user-selection-history.plan.md](persistent-user-selection-history.plan.md) | Persist local candidate learning across IMK restarts | Active |
| [candidate-anchor-resolver-fix.plan.md](candidate-anchor-resolver-fix.plan.md) | Candidate-window geometry resolver behavior | Active |
| [candidate-panel-interaction-accessibility.plan.md](candidate-panel-interaction-accessibility.plan.md) | Harden host-shortcut symbol cleanup, VoiceOver press, and pointer paging | Active |
| [candidate-page-navigation.plan.md](candidate-page-navigation.plan.md) | PageDown/PageUp offset-preserving candidate paging | Active |
| [candidate-panel-adaptive-layout.plan.md](candidate-panel-adaptive-layout.plan.md) | Measurement-first adaptive candidate panel layout | Active |
| [candidate-panel-row-builder-refactor.plan.md](candidate-panel-row-builder-refactor.plan.md) | Share candidate-panel row ordering between state and renderer | Active |
| [native-candidate-panel-spotlight-ui.plan.md](native-candidate-panel-spotlight-ui.plan.md) | macOS-native compact candidate panel styling and Spotlight window-level fix | Active |
| [candidate-panel-lifecycle-teardown.plan.md](candidate-panel-lifecycle-teardown.plan.md) | Hide, sequence, and invalidate candidate-panel frames across commit, deactivate, close, and stale async updates | Active |
| [candidate-panel-search-overlay-placement.plan.md](candidate-panel-search-overlay-placement.plan.md) | Place the candidate panel above Spotlight search overlays while preserving ordinary text-field placement | Active |
| [inputmethod-visible-candidates-punctuation.plan.md](inputmethod-visible-candidates-punctuation.plan.md) | Visible candidate, process-global punctuation, Space commit, and anchoring alignment | Active |
| [input-symbol-punctuation-policy.plan.md](input-symbol-punctuation-policy.plan.md) | Earlier punctuation/width policy, absorbed by process-global mode semantics | Absorbed |
| [input-mode-feedback-punctuator-candidates.plan.md](input-mode-feedback-punctuator-candidates.plan.md) | Add transient mode feedback, mature punctuator decisions, and panel-backed symbol candidates | Active |
| [input-mode-shortcuts-width-feedback.plan.md](input-mode-shortcuts-width-feedback.plan.md) | Earlier Shift+Space width-feedback slice, absorbed by process/global native synchronization | Absorbed |
| [input-mode-punctuation-linkage.plan.md](input-mode-punctuation-linkage.plan.md) | Share one host-lifetime mode across apps, link punctuation to text mode, and keep numeric periods ASCII | Active |
| [rime-mode-option-sync.plan.md](rime-mode-option-sync.plan.md) | Synchronize process-wide mode options into native Rime and complete character-width/quote semantics | Active |
| [inputmethod-main-thread-performance.plan.md](inputmethod-main-thread-performance.plan.md) | Keep IMK key handling responsive under larger lexicon and async provider work | Active |
| [input-method-first-key-performance.plan.md](input-method-first-key-performance.plan.md) | Reduce post-install/process-cold first-key stall and repeated hot-path overhead | Active |
| [input-method-first-key-review-followup.plan.md](input-method-first-key-review-followup.plan.md) | Resolve PR #150 first-key performance review regressions | Active |
| [input-debug-diagnostics-consolidation.plan.md](input-debug-diagnostics-consolidation.plan.md) | Consolidate privacy-safe debug and performance diagnostics for input hot-path investigations | Active |
| [ai-recommendation-placeholder-latency.plan.md](ai-recommendation-placeholder-latency.plan.md) | Keep eligible real-time AI recommendation waits visible with a fixed spinner placeholder and shorter debounce | Active |
| [settings-chinese-default-copy.plan.md](settings-chinese-default-copy.plan.md) | Use Simplified Chinese as the default Settings and input-method menu copy while retaining explicit English resources | Active |
| [settings-user-facing-control-center.plan.md](settings-user-facing-control-center.plan.md) | Redesign Settings around overview, AI, input experience, candidate panel, lexicons, privacy, and advanced troubleshooting | Active |
| [inputmethod-async-keypath-supervisor.plan.md](inputmethod-async-keypath-supervisor.plan.md) | Fully asynchronous IMK key path with cancellable candidate, AI, anchor, and panel tasks | Active |
| [rime-conversion-lexical-ai.plan.md](rime-conversion-lexical-ai.plan.md) | Optional librime bridge, synchronous base candidate hot path, and AI lexical profile context | Active |
| [rime-userdb-lexical-profile.plan.md](rime-userdb-lexical-profile.plan.md) | Persist AI lexical profile from Rime userdb frequency plus recent KnowType commits/selections | Active |
| [input-runtime-boundaries.plan.md](input-runtime-boundaries.plan.md) | Separate Rime hot path, candidate panel presentation, AI patches, and Rime maintenance side effects | Active |
| [input-turn-sequence-hardening.plan.md](input-turn-sequence-hardening.plan.md) | Validate and trace input turn effect ordering without adding another executor | Active |
| [input-turn-sequencing-runtime-refactor.plan.md](input-turn-sequencing-runtime-refactor.plan.md) | Extract explicit input-turn side-effect ordering from the coordinator | Active |
| [input-client-composition-writer-refactor.plan.md](input-client-composition-writer-refactor.plan.md) | Extract host composition write state and owned marked-text cleanup from the coordinator | Active |
| [input-selection-history-runtime-refactor.plan.md](input-selection-history-runtime-refactor.plan.md) | Extract local prefix-selection history filtering, recent cache, event payload, and persistence delegation from the coordinator | Active |
| [session-suggestion-pipeline-refactor.plan.md](session-suggestion-pipeline-refactor.plan.md) | Rename the session suggestion pipeline boundary and remove the obsolete InputMethodPipeline name without a compatibility alias | Active |
| [rime-only-hotpath-performance.plan.md](rime-only-hotpath-performance.plan.md) | Retire production local conversion fallback and enforce Rime-only hot-path performance budgets | Active |
| [rime-native-interaction-polish.plan.md](rime-native-interaction-polish.plan.md) | Align marked text, arrows, pages, numbers, symbols, and AI shortcuts with Rime-native IME behavior | Active |
| [direct-space-digit-passthrough.plan.md](direct-space-digit-passthrough.plan.md) | Pass idle Space and digits through while preserving active Rime candidate shortcuts | Active |
| [input-client-compatibility-policy.plan.md](input-client-compatibility-policy.plan.md) | Initial host compatibility write modes, superseded by decoupled carrier policy | Absorbed |
| [native-imk-settings-menu.plan.md](native-imk-settings-menu.plan.md) | Native IMK input-menu settings entry and compatibility prefPane fallback | Active |
| [system-settings-prefpane-cache-cleanup.plan.md](system-settings-prefpane-cache-cleanup.plan.md) | Remove stale System Settings prefPane cache after default local installs | Active |
| [install-upgrade-rollback-experience.plan.md](install-upgrade-rollback-experience.plan.md) | Traceable local installs, app backups, rollback, and dynamic diagnostics status | Active |
| [inputmethod-install-integrity.plan.md](inputmethod-install-integrity.plan.md) | Fail-closed rollback integrity, PreferencePane identity guards, and aligned local bundle versions | Active |
| [install-user-data-isolation.plan.md](install-user-data-isolation.plan.md) | Keep local install, rollback, and repair from launching the host or mutating user data | Active |
| [inputmethod-install-canonical-registration.plan.md](inputmethod-install-canonical-registration.plan.md) | Quiesce the old IMK host before local installs and register only the canonical installed app path | Active |
| [imk-host-cold-start-no-userdata-write.plan.md](imk-host-cold-start-no-userdata-write.plan.md) | Keep IMK host prelaunch from initializing Rime, provider, or AI learning user data | Active |
| [inputmethod-startup-registration.plan.md](inputmethod-startup-registration.plan.md) | Keep normal IMK host startup serve-only while explicit installer and repair commands own registration waits | Active |
| [input-source-layer-model.plan.md](input-source-layer-model.plan.md) | Earlier parent/mode separation plan, superseded by menu-visible mode registration | Absorbed |
| [input-source-parent-anchor-registration.plan.md](input-source-parent-anchor-registration.plan.md) | Earlier parent-anchor enablement plan, superseded by menu-visible mode registration | Absorbed |
| [input-source-single-source-model.plan.md](input-source-single-source-model.plan.md) | Parent-only single-source attempt, absorbed after menu-bar switching failed | Absorbed |
| [input-source-menu-visible-mode-registration.plan.md](input-source-menu-visible-mode-registration.plan.md) | Restore parent plus one visible `.Hans` input mode so KnowType appears in the menu bar | Active |
| [native-settings-ui-polish.plan.md](native-settings-ui-polish.plan.md) | Chinese macOS-native sidebar settings UI for the IMK preferences window | Active |
| [segmented-candidate-selection.plan.md](segmented-candidate-selection.plan.md) | Raw-span candidate rows and segmented confirmation behavior | Active |
| [ai-capability-runtime-layer.plan.md](ai-capability-runtime-layer.plan.md) | Separate AI recommendation, context memory, correction-instruction, and health layers from the IMK key path | Active |
| [traditional-lexicon-extension.plan.md](traditional-lexicon-extension.plan.md) | Authorized local lexicon extension path | Active |
| [traditional-lexicon-resource-loader.plan.md](traditional-lexicon-resource-loader.plan.md) | JSON/TSV resource loader for local lexicons | Active |
| [traditional-lexicon-catalog.plan.md](traditional-lexicon-catalog.plan.md) | Multi-resource local lexicon catalog and diagnostics | Active |
| [traditional-lexicon-file-source.plan.md](traditional-lexicon-file-source.plan.md) | File and directory loading for local lexicon resources | Active |
| [bundled-seed-lexicon-resource.plan.md](bundled-seed-lexicon-resource.plan.md) | Bundled TSV seed lexicon resource path | Active |
| [runtime-lexicon-directory.plan.md](runtime-lexicon-directory.plan.md) | Runtime directory loading for user-owned local lexicons | Active |
| [runtime-lexicon-default-refresh.plan.md](runtime-lexicon-default-refresh.plan.md) | Avoid stale default-engine caches for lexicon iteration | Active |
| [runtime-lexicon-session-refresh.plan.md](runtime-lexicon-session-refresh.plan.md) | Refresh running IMK sessions when local lexicon resources change | Active |
| [lexicon-directory-resolver.plan.md](lexicon-directory-resolver.plan.md) | Shared directory discovery for runtime and settings lexicons | Active |
| [lexicon-settings-status.plan.md](lexicon-settings-status.plan.md) | Settings status for local lexicon directories and diagnostics | Active |
| [lexicon-sample-resource-action.plan.md](lexicon-sample-resource-action.plan.md) | Settings action for creating a sample TSV lexicon | Active |
| [managed-lexicon-pack-installer.plan.md](managed-lexicon-pack-installer.plan.md) | License-aware recommended lexicon pack install path | Active |
| [provider-runtime-seeded-defaults.plan.md](provider-runtime-seeded-defaults.plan.md) | Shared seeded provider defaults for settings and runtime | Active |
| [provider-connection-diagnostics.plan.md](provider-connection-diagnostics.plan.md) | Settings-side provider connection tests without saving draft secrets | Active |
| [provider-profile-concurrency-redaction.plan.md](provider-profile-concurrency-redaction.plan.md) | Transactional cross-process provider settings, immutable credentials, and privacy-safe endpoint diagnostics | Active |
| [provider-api-contracts-template-rendering.plan.md](provider-api-contracts-template-rendering.plan.md) | Current provider model/API contracts and deterministic Custom HTTP template rendering | Active |
| [ai-runtime-config-singleflight.plan.md](ai-runtime-config-singleflight.plan.md) | Reload provider generations without restart and serialize process-wide context digest | Active |
| [context-digest-backlog-performance.plan.md](context-digest-backlog-performance.plan.md) | Bound pending Context Digest work, requests, and processed archive retention | Active |
| [settings-provider-profile-editing-policy-refactor.plan.md](settings-provider-profile-editing-policy-refactor.plan.md) | Extract Settings provider draft validation, save planning, secret mutation, and connection-test configuration from the ViewModel | Active |
| [provider-failure-continuation-fallback.plan.md](provider-failure-continuation-fallback.plan.md) | Avoid replacing provider failures with local mock continuation text | Active |
| [ai-timeout-diagnostics.plan.md](ai-timeout-diagnostics.plan.md) | AI recommendation 10-second runtime timeout and privacy-preserving substate diagnostics | Active |
| [ai-structured-output-contract.plan.md](ai-structured-output-contract.plan.md) | Provider-level structured output contract and diagnosable AI no-recommendation reasons | Active |
| [ai-continuation-prompt-reliability.plan.md](ai-continuation-prompt-reliability.plan.md) | Task-specific suffix-generation prompt and ENV marker repair for reliable AI continuation | Active |
| [prefix-repair-punctuation.plan.md](prefix-repair-punctuation.plan.md) | Preserve suffix punctuation while repairing repeated locked prefixes | Active |
| [ai-candidate-hints-lock-prefix.plan.md](ai-candidate-hints-lock-prefix.plan.md) | Keep unselected Rime candidates as AI hints instead of locked prefixes | Active |
| [ai-remove-candidate-hints-bias.plan.md](ai-remove-candidate-hints-bias.plan.md) | Remove current-page Rime candidate hints from real-time AI continuation context | Active |
| [ai-trigger-stability-no-hints.plan.md](ai-trigger-stability-no-hints.plan.md) | Stabilize three-character raw-input AI triggers without reintroducing candidate hints | Active |
| [ai-accepted-learning.plan.md](ai-accepted-learning.plan.md) | Locally record accepted AI recommendations and summarize them into the bounded lexical profile | Active |
| [accepted-learning-lexical-profile-refresh.plan.md](accepted-learning-lexical-profile-refresh.plan.md) | Refresh persistent lexical profile after accepted-AI summary rebuilds become ready | Active |
| [accepted-learning-controls.plan.md](accepted-learning-controls.plan.md) | Local status, rebuild, and clear controls for accepted AI learning | Active |
| [ai-accepted-feedback-learning.plan.md](ai-accepted-feedback-learning.plan.md) | Learn only from verified edits inside recently accepted AI text spans | Active |
| [provider-live-smoke-timeout-alignment.plan.md](provider-live-smoke-timeout-alignment.plan.md) | Align env-gated provider live smoke timeout with the AI runtime budget | Active |
| [provider-live-smoke-model-alignment.plan.md](provider-live-smoke-model-alignment.plan.md) | Align env-gated continuation live smoke with the explicit product model under test | Active |
| [ai-secret-only-privacy-gate.plan.md](ai-secret-only-privacy-gate.plan.md) | Restrict real-time AI disabled state to secret-like text and filter secret candidate hints | Active |
| [imk-owned-marked-range-commit.plan.md](imk-owned-marked-range-commit.plan.md) | Prevent cursor misplacement by ignoring stale host marked ranges on ordinary IMK writes | Active |
| [imk-default-mouse-commit.plan.md](imk-default-mouse-commit.plan.md) | Restore InputMethodKit's default click-outside composition commit | Active |
| [input-mode-and-punctuation-state.plan.md](input-mode-and-punctuation-state.plan.md) | Earlier explicit mode-state slice, absorbed by the process runtime | Absorbed |
| [input-mode-preferences.plan.md](input-mode-preferences.plan.md) | Earlier per-app preference slice, absorbed by global-width persistence | Absorbed |
| [symbol-mode-and-input-behavior.plan.md](symbol-mode-and-input-behavior.plan.md) | Punctuation and commit behavior slice | Active |
| [settings-debug-selection-guidance.plan.md](settings-debug-selection-guidance.plan.md) | Settings Debug Install guidance for diagnose/select/manual gates | Active |
| [source-notes-directory-structure.plan.md](source-notes-directory-structure.plan.md) | Mirror repository ownership boundaries inside `doc/src` | Active |
| [main-tag-release-ci.plan.md](main-tag-release-ci.plan.md) | Main branch bootstrap and tag-triggered local MVP release packages | Active |
| [developer-preview-dmg-release.plan.md](developer-preview-dmg-release.plan.md) | Developer Preview DMG as the default GitHub Release download while notarized pkg is unavailable | Active |

## Local IME And Tooling References

| Document | Purpose | Status |
|---|---|---|
| [macos-ime-smoke-diagnostics.plan.md](macos-ime-smoke-diagnostics.plan.md) | Installed-bundle and Text Input Source diagnostics before manual acceptance | Active |
| [macos-ime-acceptance-harness.plan.md](macos-ime-acceptance-harness.plan.md) | Repeatable local IME acceptance harness and report template | Active |
| [inputmethod-script-ci-smoke.plan.md](inputmethod-script-ci-smoke.plan.md) | CI coverage for local IMK helper scripts and bundle packaging smoke checks | Active |
| [install-selection-status.plan.md](install-selection-status.plan.md) | Report local install selection requests while deferring status to diagnostics | Active |
| [input-source-selection-helper.plan.md](input-source-selection-helper.plan.md) | Standalone helper for retrying KnowType input-source selection | Active |
| [input-source-selection-persistence.plan.md](input-source-selection-persistence.plan.md) | Context-aware local Text Input Source selection verification | Active |
| [input-source-display-name.plan.md](input-source-display-name.plan.md) | Localized macOS input-source display name and TIS cache diagnostics | Active |
| [input-source-selection-activation.plan.md](input-source-selection-activation.plan.md) | Installed-app activation path and selection-chain diagnostics | Active |
| [local-input-source-system-policy.plan.md](local-input-source-system-policy.plan.md) | macOS 15 local SystemPolicyRule generation for Apple Development testing | Active |
| [local-input-source-switching-repair.plan.md](local-input-source-switching-repair.plan.md) | Repair stale local TIS/LaunchServices state and authorization guidance | Active |
| [install-script-deduplicate-local-bundles.plan.md](install-script-deduplicate-local-bundles.plan.md) | Deduplicate local KnowType IMK bundles and stale LaunchServices records | Active |
| [input-source-support-shared-cleanup.plan.md](input-source-support-shared-cleanup.plan.md) | Share duplicated TIS and LaunchServices support helpers between the installed app and input-source CLI | Active |

## Delivered Or Recently Absorbed Work

| Document | Purpose | Status |
|---|---|---|
| [option-r-polish-removal.plan.md](option-r-polish-removal.plan.md) | Remove the Option+R rewrite workflow and make locked-prefix rewriting unsupported | Delivered |
| [release-0.2.6.plan.md](release-0.2.6.plan.md) | Prepare and publish the KnowType v0.2.6 Developer Preview release | Delivered |
| [release-0.2.5.plan.md](release-0.2.5.plan.md) | Prepare and publish the KnowType v0.2.5 Developer Preview release | Delivered |
| [release-0.2.4.plan.md](release-0.2.4.plan.md) | Prepare and publish the KnowType v0.2.4 Developer Preview release | Delivered |
| [release-0.2.3.plan.md](release-0.2.3.plan.md) | Prepare and publish the KnowType v0.2.3 Developer Preview release | Delivered |
| [ai-recommendation-cancellation-sequencing.plan.md](ai-recommendation-cancellation-sequencing.plan.md) | Restore best-effort cancellation for stale started AI transports without poisoning provider health, validated by local debug-log summary | Delivered |
| [input-commit-decision-runtime-refactor.plan.md](input-commit-decision-runtime-refactor.plan.md) | Extract Space, Tab, Option-number, selected-row, AI acceptance, and prefix-learning commit decisions from the coordinator | Delivered |
| [ai-recommendation-stability-latency.plan.md](ai-recommendation-stability-latency.plan.md) | Original AI dispatch debounce and stale-drop stabilization; later follow-up restores stale transport cancellation | Delivered |
| [input-composition-lifecycle-runtime-refactor.plan.md](input-composition-lifecycle-runtime-refactor.plan.md) | Extract composition begin/finish lifecycle planning and trace-once state from the coordinator | Delivered |
| [input-commit-application-runtime-refactor.plan.md](input-commit-application-runtime-refactor.plan.md) | Extract commit-result planning and side-effect context construction from the coordinator | Delivered |
| [input-refactor-regression-audit.plan.md](input-refactor-regression-audit.plan.md) | Lock coordinator-level behavior after the input-method runtime extraction sequence | Delivered |
| [input-composition-state-runtime-refactor.plan.md](input-composition-state-runtime-refactor.plan.md) | Extract raw input, composition buffer, composition id/revision, and delete-count state from the coordinator | Delivered |
| [input-suggestion-state-runtime-refactor.plan.md](input-suggestion-state-runtime-refactor.plan.md) | Extract current suggestion state, commit snapshots, and no-provider fallback cleanup from the coordinator | Delivered |
| [input-lexical-commit-runtime-refactor.plan.md](input-lexical-commit-runtime-refactor.plan.md) | Extract local lexical commit, selection-history, refresh scheduling, and event payload orchestration from the coordinator | Delivered |
| [input-native-candidate-navigation-runtime-refactor.plan.md](input-native-candidate-navigation-runtime-refactor.plan.md) | Extract Rime/native candidate selection, highlight, paging, and panel-selection mapping from the coordinator | Delivered |
| [input-candidate-panel-publication-runtime-refactor.plan.md](input-candidate-panel-publication-runtime-refactor.plan.md) | Extract candidate-panel publication, visibility, async refresh, and delayed re-anchor lifecycle from the coordinator | Delivered |
| [input-ai-acceptance-runtime-refactor.plan.md](input-ai-acceptance-runtime-refactor.plan.md) | Extract post-commit AI acceptance learning and feedback side effects from the coordinator | Delivered |
| [input-ai-recommendation-runtime-refactor.plan.md](input-ai-recommendation-runtime-refactor.plan.md) | Extract real-time AI recommendation request lifecycle from the coordinator | Delivered |
| [input-ai-recommendation-schedule-policy-refactor.plan.md](input-ai-recommendation-schedule-policy-refactor.plan.md) | Extract real-time AI recommendation schedule eligibility from the coordinator | Delivered |
| [input-method-decouple-host-carrier.plan.md](input-method-decouple-host-carrier.plan.md) | Decouple code-app input defaults from host marked-text carrier selection and remove Codex carrier remnants | Delivered |
| [input-client-host-profile-preedit.plan.md](input-client-host-profile-preedit.plan.md) | Host profile carrier table and commit-only candidate-panel preedit row | Delivered |
| [input-client-placeholder-composition.plan.md](input-client-placeholder-composition.plan.md) | Commit-only host placeholder composition and owned marked-text cleanup | Delivered |
| [imk-server-stable-connection.plan.md](imk-server-stable-connection.plan.md) | Stable IMK server connection name aligned across plist, Swift constants, shell scripts, and installed endpoint verification | Delivered |
| [imk-session-architecture.plan.md](imk-session-architecture.plan.md) | Thin IMK controller and explicit session separation | Delivered |
| [inputmethod-native-candidates-fix.plan.md](inputmethod-native-candidates-fix.plan.md) | Native-style candidate panel behavior | Delivered |
| [native-candidate-panel-style.plan.md](native-candidate-panel-style.plan.md) | Compact macOS candidate panel styling | Delivered |
| [preferences-install-debug.plan.md](preferences-install-debug.plan.md) | Settings and local install/debug workflow | Delivered |
| [system-settings-preference-pane.plan.md](system-settings-preference-pane.plan.md) | PreferencePane and IMK preferences settings hosts | Delivered |

## Maintenance Rules

- Add or update a plan before implementing feature, fix, refactor, or behavior
  changes that need design review.
- Update this index in the same change that adds, absorbs, or retires a plan.
- Move stable behavior summaries into `doc/` and source notes after a plan
  ships.
- Mark old plans `Absorbed` or `Retire Candidate` before deleting them, unless
  the deletion is part of a dedicated docs cleanup.
- Do not duplicate long architecture explanations here; link to the relevant
  current-state document instead.
