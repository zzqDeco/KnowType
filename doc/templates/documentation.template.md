# <Document Title>

Use this template for current-state project documentation under `doc/`.
Keep the document focused on how KnowType works now. Put implementation history,
discarded alternatives, and branch-local work in `plan/` instead.

## Purpose

- State the boundary this document owns.
- Link to related docs instead of duplicating their details.

## Current State

- Describe the current behavior, data flow, or operational process.
- Call out user-visible behavior separately from internal implementation details.
- Keep examples short and current.

## Contracts

- Record cross-module contracts, file formats, command behavior, shortcuts, or
  validation rules that callers must preserve.
- Name the owner module when a rule belongs to a specific package target.

## Validation

- List the unit tests, scripts, manual acceptance steps, or diagnostics that
  prove this behavior today.
- Be explicit when a behavior still depends on local manual macOS verification.

## Related Docs

- [Architecture](../architecture.plan.md)
- [Interfaces](../interfaces.plan.md)
- [Source Notes](../src/README.md)
