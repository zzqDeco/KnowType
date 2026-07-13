# AGENTS.md

Guidance for coding agents working in KnowType.

## Project Overview

KnowType is a macOS Chinese/English input method with AI-assisted continuation.

- Language: Swift 6.2
- Core package: Swift Package Manager
- Input method host: AppKit + InputMethodKit
- Candidate UI: custom AppKit panel
- Settings app: SwiftUI

The product rule is strict: correction may refine the prefix, but continuation must never rewrite the locked prefix. The input method does not provide a locked-prefix rewrite action.

## Commands

```bash
swift build
swift test
```

For documentation-only changes, run at least:

```bash
git diff --check
```

## Architecture

- `Sources/KnowTypeCore/`: product models, local correction, text protection, prefix-locked continuation.
- `Sources/KnowTypeProviders/`: provider configuration, HTTP client abstraction, response normalization, and protocol adapters.
- `Sources/KnowTypeInputMethod/`: IMK controller, input actions, candidate state, candidate panel, and key behavior.
- `Sources/KnowTypeInputMethodApp/`: local input method app entry point.
- `Sources/KnowTypeSettingsUI/`: shared SwiftUI settings and provider profile editing.
- `Sources/KnowTypeSettingsApp/`: standalone settings app host.
- `Sources/KnowTypePreferencePane/`: System Settings preference pane host.
- `Tests/`: unit tests for product behavior, providers, and input-method logic.
- `doc/`: current architecture, interface, source notes, and acceptance docs.
- `plan/`: active or recently delivered implementation plans.

## Provider Rules

Every provider adapter must normalize into `LLMResponse`.

Do not leak provider-specific response shapes into `KnowTypeCore` or `KnowTypeInputMethod`.

Continuation prompts must ask for continuation text only. The client must still sanitize responses because providers may return full sentences.

## Branching

- Stable branch: `main`
- Integration branch: `dev`
- Topic branches:
  - `feature/<desc>`
  - `fix/<desc>`
  - `docs/<desc>`
  - `refactor/<desc>`
  - `test/<desc>`
  - `release/<version>`

## Commits

Use Conventional Commits:

```text
<type>(<scope>): <subject>
```

Common scopes:

- `core`
- `providers`
- `input-method`
- `settings`
- `docs`
- `build`
- `tests`

## Documentation Sync

For feature, fix, or refactor work:

1. Update or add a plan under `plan/` when the work is still being designed or reviewed.
2. Update `doc/architecture.plan.md` or `doc/interfaces.plan.md` when behavior, data flow, protocols, or shortcuts change.
3. Add or update source notes under `doc/src/<repo-path>/...plan.md` for important source-file responsibilities. Mirror the repository layout, for example `doc/src/Sources/KnowTypeCore/...` or `doc/src/scripts/...`.
4. Update `README.md` and `README_CN.md` for user-visible setup or behavior changes.
5. Update `doc/README.md` or `plan/README.md` when adding or retiring documentation files.

For docs-only cleanup, keep prose concise and current-state focused. Do not turn `README.md` into a full design history.

## Documentation Standards

- Use `plan/templates/implementation-plan.template.md` for new active work plans.
- Use `plan/templates/delivered-plan.template.md` when converting shipped work into a short delivered record.
- Use `doc/templates/documentation.template.md` for new current-state docs under `doc/`.
- Use `doc/templates/source-note.template.md` for new source notes under `doc/src/`.
- Keep `README.md` and `README_CN.md` shaped like GitHub project entry pages: what the project is, current status, quick start, local install, configuration, privacy, docs, development, and known non-goals.
- Keep stable behavior in `doc/`; keep implementation intent, sequencing, and branch-local decisions in `plan/`.
- Source notes are required for public contracts, cross-module boundaries, provider adapters, IMK/AppKit seams, persistence formats, local scripts, and files with non-obvious privacy or prefix-lock behavior. They are not required for every test file.
- Update indexes in the same change that adds, absorbs, or retires docs:
  - `doc/README.md` for top-level docs and templates.
  - `doc/src/README.md` for source notes.
  - `plan/README.md` for implementation plans and delivered records.
- Plan statuses are `Active`, `Delivered`, `Absorbed`, and `Retire Candidate`. Retire a plan only after stable behavior is documented in `doc/` or no longer relevant.
- For documentation-only changes, run `git diff --check` and check that README/index links point at existing files. Run `swift test` only when Swift code or script behavior changes.

## Review Checklist

- Prefix candidates and continuation candidates remain separate.
- Continuation candidates do not repeat or rewrite the locked prefix.
- Level 0 inputs do not call cloud providers.
- Technical tokens such as `API`, `JSON`, `macOS`, `InputMethodKit`, `snake_case`, and `camelCase` are preserved.
- Adapter tests cover request mapping and response parsing when provider behavior changes.
- Input-method behavior tests cover shortcut, candidate, paging, or punctuation changes.
- `swift test` passes before finalizing code changes.
