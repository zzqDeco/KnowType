# <Source File Or Subsystem>

Use this template for source notes under `doc/src/`. The path should mirror the
repository path, for example `doc/src/Sources/KnowTypeCore/Foo.plan.md` for
`Sources/KnowTypeCore/Foo.swift`.

## Responsibility

- State what this file or subsystem owns.
- Keep the note at the level of intent and boundaries, not line-by-line code.

## Boundaries

- State what must not be added here.
- Name adjacent owners when logic should stay in another module.

## Behavior Notes

- Capture non-obvious invariants, persistence paths, host-app quirks, privacy
  rules, or testing seams.
- Prefer current behavior over historical branch context.

## Tests

- List the focused tests or scripts that should be updated when this file's
  responsibility changes.
