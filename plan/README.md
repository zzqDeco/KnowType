# KnowType Plan Index

`plan/` stores active or recently delivered implementation plans. It is intentionally smaller than a project wiki: once a plan is obsolete and its behavior is documented in `doc/`, it can be retired through a docs cleanup PR.

## Active MVP Work

| Document | Purpose | Status |
|---|---|---|
| [multi-api-v1.plan.md](multi-api-v1.plan.md) | Provider abstraction, protocol compatibility, correction, continuation, and project workflow | Active reference |
| [chinese-engine-foundation.plan.md](chinese-engine-foundation.plan.md) | MVP Chinese input engine foundation and candidate behavior | Active reference |
| [candidate-anchor-resolver-fix.plan.md](candidate-anchor-resolver-fix.plan.md) | Mature candidate-window geometry resolver | Active reference |
| [privacy-app-rules-mvp.plan.md](privacy-app-rules-mvp.plan.md) | Level 0 no-provider routing and protected app rules | Active reference |
| [persistent-user-selection-history.plan.md](persistent-user-selection-history.plan.md) | Local candidate learning persisted across IMK restarts | Active reference |
| [candidate-page-navigation.plan.md](candidate-page-navigation.plan.md) | Candidate PageDown/PageUp offset-preserving behavior | Active reference |
| [traditional-lexicon-extension.plan.md](traditional-lexicon-extension.plan.md) | Authorized local lexicon extension path for the Chinese engine | Active reference |
| [traditional-lexicon-resource-loader.plan.md](traditional-lexicon-resource-loader.plan.md) | JSON/TSV resource loader for authorized local lexicons | Active reference |
| [traditional-lexicon-catalog.plan.md](traditional-lexicon-catalog.plan.md) | Multi-resource catalog and diagnostics for local lexicons | Active reference |
| [traditional-lexicon-file-source.plan.md](traditional-lexicon-file-source.plan.md) | File and directory loading for authorized local lexicon resources | Active reference |
| [bundled-seed-lexicon-resource.plan.md](bundled-seed-lexicon-resource.plan.md) | Package-resource seed lexicon loaded through the local resource path | Active reference |
| [runtime-lexicon-directory.plan.md](runtime-lexicon-directory.plan.md) | Runtime directory loading for user-owned local lexicons | Active reference |
| [lexicon-settings-status.plan.md](lexicon-settings-status.plan.md) | Settings status for local lexicon directories and diagnostics | Active reference |
| [lexicon-directory-resolver.plan.md](lexicon-directory-resolver.plan.md) | Shared directory discovery for runtime and settings local lexicons | Active reference |
| [runtime-lexicon-default-refresh.plan.md](runtime-lexicon-default-refresh.plan.md) | Avoid stale default-engine caches for local lexicon iteration | Active reference |
| [runtime-lexicon-session-refresh.plan.md](runtime-lexicon-session-refresh.plan.md) | Refresh running IMK sessions when local lexicon resources change | Active reference |
| [lexicon-sample-resource-action.plan.md](lexicon-sample-resource-action.plan.md) | Settings action for creating a known-good sample TSV lexicon | Active reference |
| [provider-runtime-seeded-defaults.plan.md](provider-runtime-seeded-defaults.plan.md) | Shared seeded provider defaults for settings and runtime loading | Active reference |
| [provider-connection-diagnostics.plan.md](provider-connection-diagnostics.plan.md) | Settings-side provider connection testing without persisting draft secrets | Active reference |
| [provider-failure-continuation-fallback.plan.md](provider-failure-continuation-fallback.plan.md) | Keep provider-backed continuation honest by not replacing failures with local fallback text | Active reference |
| [input-mode-preferences.plan.md](input-mode-preferences.plan.md) | Persist punctuation language and symbol width preferences shared by settings and IMK runtime | Active reference |
| [macos-ime-smoke-diagnostics.plan.md](macos-ime-smoke-diagnostics.plan.md) | Local installed-bundle and Text Input Source diagnostics before manual IMK acceptance | Active reference |
| [install-selection-status.plan.md](install-selection-status.plan.md) | Report local install selection requests and defer system status to diagnostics | Active reference |
| [input-source-selection-helper.plan.md](input-source-selection-helper.plan.md) | Standalone helper for retrying KnowType input-source selection before manual typing acceptance | Active reference |
| [input-source-selection-persistence.plan.md](input-source-selection-persistence.plan.md) | Context-aware local Text Input Source selection verification | Active reference |
| [input-source-display-name.plan.md](input-source-display-name.plan.md) | Localized macOS input-source display name and stale TIS cache diagnostics | Active reference |
| [input-source-selection-activation.plan.md](input-source-selection-activation.plan.md) | Installed-app activation path and local selection-chain diagnostics | Active reference |
| [local-input-source-system-policy.plan.md](local-input-source-system-policy.plan.md) | macOS 15 local SystemPolicyRule generation for Apple Development input-method testing | Active reference |
| [inputmethod-script-ci-smoke.plan.md](inputmethod-script-ci-smoke.plan.md) | CI coverage for local IMK helper scripts and bundle packaging smoke checks | Active reference |
| [macos-ime-acceptance-harness.plan.md](macos-ime-acceptance-harness.plan.md) | Repeatable local IME acceptance harness and report template | Active reference |
| [settings-debug-selection-guidance.plan.md](settings-debug-selection-guidance.plan.md) | Settings Debug Install guidance for diagnose/select/manual typing gates | Active reference |
| [source-notes-directory-structure.plan.md](source-notes-directory-structure.plan.md) | Mirror repository ownership boundaries inside `doc/src` | Active reference |

## Delivered MVP Slices

| Document | Purpose | Status |
|---|---|---|
| [imk-session-architecture.plan.md](imk-session-architecture.plan.md) | Thin IMK controller and session separation | Delivered, keep until architecture docs fully absorb it |
| [inputmethod-native-candidates-fix.plan.md](inputmethod-native-candidates-fix.plan.md) | Native-style candidate panel behavior | Delivered, keep as UI reference |
| [native-candidate-panel-style.plan.md](native-candidate-panel-style.plan.md) | Compact macOS candidate panel styling | Delivered, keep as UI reference |
| [preferences-install-debug.plan.md](preferences-install-debug.plan.md) | Settings and local install/debug workflow | Delivered, keep as settings reference |
| [symbol-mode-and-input-behavior.plan.md](symbol-mode-and-input-behavior.plan.md) | Punctuation and commit behavior slice | Delivered, pending follow-up input-mode state work |

## Maintenance Rules

- Keep `plan/` focused on implementable work and recently merged decisions.
- Move stable behavior summaries into [doc/](../doc/README.md).
- Update this index whenever adding, merging, or retiring a plan.
- Do not duplicate long architecture explanations here; link to the relevant doc instead.
