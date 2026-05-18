# scripts/lib/inputsource-tool.sh

## Responsibility

Provides shell helpers for building and calling the
`knowtype-inputsource-tool` executable from install, selection, diagnostic, and
repair scripts.

## Boundaries

- TIS behavior lives in `KnowTypeInputSourceTool`.
- Shell wrappers should not duplicate inline Swift snippets for input-source
  registration or selection.

## Behavior Notes

- Helper calls should keep read-only diagnostics distinct from mutating
  registration, dedupe, and selection operations.
- Failure messages should point users toward diagnostics and manual acceptance
  rather than claiming typing behavior was proven.

## Tests

- `scripts/smoke-inputmethod-install.sh`
