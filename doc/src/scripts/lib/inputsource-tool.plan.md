# scripts/lib/inputsource-tool.sh and inputsource-ids.sh

## Responsibility

Provides shell helpers for building and calling the
`knowtype-inputsource-tool` executable from diagnostic scripts.
`inputsource-ids.sh` mirrors the Swift input-source constants for shell scripts.

## Boundaries

- TIS diagnostic behavior lives in `KnowTypeInputSourceTool`.
- User-facing install, repair, and selection activation live in the installed
  `KnowTypeInputMethodApp` command-line path.
- Shell wrappers should not duplicate inline Swift snippets for input-source
  registration or diagnostics.

## Behavior Notes

- Helper calls should keep read-only diagnostics distinct from mutating TIS
  registration and legacy-mode disablement. User-facing activation should go
  through the installed `KnowTypeInputMethodApp`; the helper's explicit
  `repair-preferences` command is reserved for local stale `.Mode` preference
  repair and missing third-party parent anchors, and must leave unrelated input
  sources untouched.
- Shell scripts should source `inputsource-ids.sh` instead of hardcoding the
  parent/active input-source id, legacy `.Mode` cleanup ids, connection
  name, or fallback keyboard id.
- Failure messages should point users toward diagnostics and manual acceptance
  rather than claiming typing behavior was proven.

## Tests

- `scripts/smoke-inputmethod-install.sh`
