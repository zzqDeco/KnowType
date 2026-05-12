# AGENTS.md

Guidance for coding agents working in KnowType.

## Project Overview

KnowType is a macOS Chinese/English AI input method.

- Language: Swift 6.2
- Core package: Swift Package Manager
- Input method host: AppKit + InputMethodKit
- Settings app: SwiftUI, to be added after the package-level core is stable

The product rule is strict: correction may refine the prefix, but continuation must never rewrite the locked prefix. Rewriting is allowed only through explicit polish actions.

## Commands

```bash
swift build
swift test
```

## Architecture

- `Sources/KnowTypeCore/`: data models, local correction, text protection, prefix-locked continuation.
- `Sources/KnowTypeProviders/`: provider configuration, HTTP client abstraction, response normalization, and protocol adapters.
- `Sources/KnowTypeInputMethod/`: input action handling, candidate panel view model, and InputMethodKit bootstrap.
- `Tests/`: unit tests for product behavior and protocol adapters.
- `plan/`: current active implementation plans.
- `doc/`: architecture and interface documentation.

## Provider Rules

Every provider adapter must normalize into `LLMResponse`.

Do not leak provider-specific response shapes into `KnowTypeCore`.

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
- `docs`
- `build`
- `tests`

## Documentation Sync

For feature, fix, or refactor work:

1. Update or add a plan under `plan/`.
2. Update `doc/architecture.plan.md` or `doc/interfaces.plan.md` when behavior, data flow, protocols, or shortcuts change.
3. Add or update `doc/src/...plan.md` for important source files.
4. Update `README.md` and `README_CN.md` for user-visible behavior or setup changes.

## Review Checklist

- Prefix candidates and continuation candidates remain separate.
- Level 0 inputs do not call cloud providers.
- Technical tokens such as API, JSON, macOS, InputMethodKit, snake_case, and camelCase are preserved.
- Adapter tests cover request mapping and response parsing.
- `swift test` passes before finalizing.
