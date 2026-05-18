# <Plan Title>

Use this template for active implementation plans under `plan/`. A plan should
be decision-complete enough for another engineer to implement without asking for
basic scope or validation choices.

## Summary

- State the user-visible or engineering goal.
- State why the work belongs in this slice.

## Scope

- List the behavior, modules, files, scripts, or docs this work changes.
- Include non-goals when they prevent likely scope creep.

## Implementation

- Describe the intended approach at subsystem level.
- Record API, schema, file-format, shortcut, persistence, or command changes.
- Call out compatibility and migration behavior when existing data is involved.

## Test Plan

- List focused unit tests, script smoke checks, manual acceptance, and docs-only
  validation.
- Use `swift test` for code changes and at least `git diff --check` for
  documentation-only changes.

## Assumptions

- Record defaults chosen by the plan.
- Record unresolved follow-up work that is intentionally outside this slice.
