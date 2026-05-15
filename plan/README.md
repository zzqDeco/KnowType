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
