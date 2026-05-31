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
| [multi-api-v1.plan.md](multi-api-v1.plan.md) | Provider abstraction, protocol compatibility, correction, continuation, and workflow | Active |
| [chinese-engine-foundation.plan.md](chinese-engine-foundation.plan.md) | MVP Chinese input engine foundation and candidate behavior | Active |
| [chinese-lexicon-index.plan.md](chinese-lexicon-index.plan.md) | Larger-lexicon indexing path for `TraditionalInputEngine` | Active |
| [pr23-chinese-prefix-completions.plan.md](pr23-chinese-prefix-completions.plan.md) | Cleanup of useful Chinese prefix completion gaps from stale PR work | Active |
| [pinyin-cloud-fallback-policy.plan.md](pinyin-cloud-fallback-policy.plan.md) | Provider fallback policy for unknown pinyin-shaped input | Active |
| [privacy-app-rules-mvp.plan.md](privacy-app-rules-mvp.plan.md) | Level 0 no-provider routing and protected app rules | Active |
| [user-selection-ranking.plan.md](user-selection-ranking.plan.md) | Local ranking boost from recent prefix selections | Active |
| [persistent-user-selection-history.plan.md](persistent-user-selection-history.plan.md) | Persist local candidate learning across IMK restarts | Active |
| [candidate-anchor-resolver-fix.plan.md](candidate-anchor-resolver-fix.plan.md) | Candidate-window geometry resolver behavior | Active |
| [candidate-page-navigation.plan.md](candidate-page-navigation.plan.md) | PageDown/PageUp offset-preserving candidate paging | Active |
| [candidate-panel-adaptive-layout.plan.md](candidate-panel-adaptive-layout.plan.md) | Measurement-first adaptive candidate panel layout | Active |
| [native-candidate-panel-spotlight-ui.plan.md](native-candidate-panel-spotlight-ui.plan.md) | macOS-native compact candidate panel styling and Spotlight window-level fix | Active |
| [candidate-panel-lifecycle-teardown.plan.md](candidate-panel-lifecycle-teardown.plan.md) | Hide and invalidate the AppKit candidate panel across commit, deactivate, close, and stale async updates | Active |
| [candidate-panel-search-overlay-placement.plan.md](candidate-panel-search-overlay-placement.plan.md) | Place the candidate panel above Spotlight search overlays while preserving ordinary text-field placement | Active |
| [inputmethod-visible-candidates-punctuation.plan.md](inputmethod-visible-candidates-punctuation.plan.md) | Visible candidate, punctuation, Space commit, and anchoring alignment | Active |
| [inputmethod-main-thread-performance.plan.md](inputmethod-main-thread-performance.plan.md) | Keep IMK key handling responsive under larger lexicon and async provider work | Active |
| [inputmethod-async-keypath-supervisor.plan.md](inputmethod-async-keypath-supervisor.plan.md) | Fully asynchronous IMK key path with cancellable candidate, AI, anchor, and panel tasks | Active |
| [rime-conversion-lexical-ai.plan.md](rime-conversion-lexical-ai.plan.md) | Optional librime bridge, synchronous base candidate hot path, and AI lexical profile context | Active |
| [rime-userdb-lexical-profile.plan.md](rime-userdb-lexical-profile.plan.md) | Persist AI lexical profile from Rime userdb frequency plus recent KnowType commits/selections | Active |
| [input-runtime-boundaries.plan.md](input-runtime-boundaries.plan.md) | Separate Rime hot path, candidate panel presentation, AI patches, and Rime maintenance side effects | Active |
| [rime-only-hotpath-performance.plan.md](rime-only-hotpath-performance.plan.md) | Retire production local conversion fallback and enforce Rime-only hot-path performance budgets | Active |
| [rime-native-interaction-polish.plan.md](rime-native-interaction-polish.plan.md) | Align marked text, arrows, pages, numbers, symbols, and AI shortcuts with Rime-native IME behavior | Active |
| [direct-space-digit-passthrough.plan.md](direct-space-digit-passthrough.plan.md) | Pass idle Space and digits through while preserving active Rime candidate shortcuts | Active |
| [native-imk-settings-menu.plan.md](native-imk-settings-menu.plan.md) | Native IMK input-menu settings entry and compatibility prefPane fallback | Active |
| [system-settings-prefpane-cache-cleanup.plan.md](system-settings-prefpane-cache-cleanup.plan.md) | Remove stale System Settings prefPane cache after default local installs | Active |
| [install-upgrade-rollback-experience.plan.md](install-upgrade-rollback-experience.plan.md) | Traceable local installs, app backups, rollback, and dynamic diagnostics status | Active |
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
| [provider-failure-continuation-fallback.plan.md](provider-failure-continuation-fallback.plan.md) | Avoid replacing provider failures with local mock continuation text | Active |
| [ai-timeout-diagnostics.plan.md](ai-timeout-diagnostics.plan.md) | AI recommendation 10-second runtime timeout and privacy-preserving substate diagnostics | Active |
| [ai-structured-output-contract.plan.md](ai-structured-output-contract.plan.md) | Provider-level structured output contract and diagnosable AI no-recommendation reasons | Active |
| [ai-continuation-prompt-reliability.plan.md](ai-continuation-prompt-reliability.plan.md) | Task-specific suffix-generation prompt and ENV marker repair for reliable AI continuation | Active |
| [ai-candidate-hints-lock-prefix.plan.md](ai-candidate-hints-lock-prefix.plan.md) | Keep unselected Rime candidates as AI hints instead of locked prefixes | Active |
| [ai-remove-candidate-hints-bias.plan.md](ai-remove-candidate-hints-bias.plan.md) | Remove current-page Rime candidate hints from real-time AI continuation context | Active |
| [ai-trigger-stability-no-hints.plan.md](ai-trigger-stability-no-hints.plan.md) | Stabilize three-character raw-input AI triggers without reintroducing candidate hints | Active |
| [ai-accepted-learning.plan.md](ai-accepted-learning.plan.md) | Locally record accepted AI recommendations and summarize them into the bounded lexical profile | Active |
| [accepted-learning-lexical-profile-refresh.plan.md](accepted-learning-lexical-profile-refresh.plan.md) | Refresh persistent lexical profile after accepted-AI summary rebuilds become ready | Active |
| [provider-live-smoke-timeout-alignment.plan.md](provider-live-smoke-timeout-alignment.plan.md) | Align env-gated provider live smoke timeout with the AI runtime budget | Active |
| [provider-live-smoke-model-alignment.plan.md](provider-live-smoke-model-alignment.plan.md) | Align env-gated continuation live smoke with the explicit product model under test | Active |
| [ai-secret-only-privacy-gate.plan.md](ai-secret-only-privacy-gate.plan.md) | Restrict real-time AI disabled state to secret-like text and filter secret candidate hints | Active |
| [imk-owned-marked-range-commit.plan.md](imk-owned-marked-range-commit.plan.md) | Prevent cursor misplacement by ignoring stale host marked ranges on ordinary IMK writes | Active |
| [input-mode-and-punctuation-state.plan.md](input-mode-and-punctuation-state.plan.md) | Explicit input-mode state for text mode, punctuation, and width | Active |
| [input-mode-preferences.plan.md](input-mode-preferences.plan.md) | Persisted punctuation and symbol-width preferences | Active |
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

## Delivered Or Recently Absorbed Work

| Document | Purpose | Status |
|---|---|---|
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
