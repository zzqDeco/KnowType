# scripts/lib/inputsource-tool.sh and inputsource-ids.sh

## Responsibility

Provides shell helpers for building and calling the
`knowtype-inputsource-tool` executable from diagnostic, install, rollback, and
repair scripts.
`inputsource-ids.sh` mirrors the Swift input-source constants for shell scripts.

## Boundaries

- TIS diagnostic, registration, legacy cleanup, and scoped repair behavior live
  in `KnowTypeInputSourceTool`.
- Default install and rollback paths must not launch the installed
  `KnowTypeInputMethodApp`; explicit selection remains a separate preflight
  before real typing.
- Shell wrappers should not duplicate inline Swift snippets for input-source
  registration or diagnostics.

## Behavior Notes

- Helper calls should keep read-only diagnostics distinct from mutating TIS
  registration, legacy-mode disablement, and preference repair. Default
  installation uses helper `bootstrap` without `--select`; explicit repair may
  select through the helper, while manual typing acceptance still requires the
  user to select KnowType in the active target app. Scoped preference repair must
  leave unrelated input sources untouched. Enabled repairs restore the parent
  anchor plus `.Hans`; selected and history repairs stay `.Hans`-only.
- Shell scripts should source `inputsource-ids.sh` instead of hardcoding the
  parent/active input-source id, legacy `.Mode` cleanup ids, connection
  name, or fallback keyboard id.
- Failure messages should point users toward diagnostics and manual acceptance
  rather than claiming typing behavior was proven.

## Tests

- `scripts/smoke-inputmethod-install.sh`
