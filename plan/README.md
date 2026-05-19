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
| [inputmethod-visible-candidates-punctuation.plan.md](inputmethod-visible-candidates-punctuation.plan.md) | Visible candidate, punctuation, Space commit, and anchoring alignment | Active |
| [inputmethod-main-thread-performance.plan.md](inputmethod-main-thread-performance.plan.md) | Keep IMK key handling responsive under larger lexicon and async provider work | Active |
| [inputmethod-async-keypath-supervisor.plan.md](inputmethod-async-keypath-supervisor.plan.md) | Fully asynchronous IMK key path with cancellable candidate, AI, anchor, and panel tasks | Active |
| [rime-conversion-lexical-ai.plan.md](rime-conversion-lexical-ai.plan.md) | Optional librime bridge, synchronous base candidate hot path, and AI lexical profile context | Active |
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
| [input-mode-and-punctuation-state.plan.md](input-mode-and-punctuation-state.plan.md) | Explicit input-mode state for text mode, punctuation, and width | Active |
| [input-mode-preferences.plan.md](input-mode-preferences.plan.md) | Persisted punctuation and symbol-width preferences | Active |
| [symbol-mode-and-input-behavior.plan.md](symbol-mode-and-input-behavior.plan.md) | Punctuation and commit behavior slice | Active |
| [settings-debug-selection-guidance.plan.md](settings-debug-selection-guidance.plan.md) | Settings Debug Install guidance for diagnose/select/manual gates | Active |
| [source-notes-directory-structure.plan.md](source-notes-directory-structure.plan.md) | Mirror repository ownership boundaries inside `doc/src` | Active |
| [main-tag-release-ci.plan.md](main-tag-release-ci.plan.md) | Main branch bootstrap and tag-triggered local MVP release packages | Active |

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
