# Option+R Polish Removal

## Delivered Behavior

- Remove the Option+R input action, explicit-polish session state, provider task,
  candidate overlay, diagnostics, Settings copy, Demo argument, and acceptance
  steps.
- Treat unrecognized Option-modified letter keys as host shortcuts rather than
  input-method commands.
- Keep the product boundary strict: continuation may append after a locked
  prefix, but no input action may rewrite that prefix.

## Requirement History

- GitHub issue `#183` was created on 2026-07-10 at 10:05 CST.
- PR `#197` implemented the provider-backed workflow and merged on 2026-07-11
  at 12:59 CST.
- The product requirement was withdrawn on 2026-07-13 because the workflow did
  not provide enough user value to justify its interaction and runtime surface.

## Verification

- `swift build --disable-index-store`
- `swift test --disable-index-store`
- `bash -n scripts/*.sh scripts/lib/*.sh`
- `git diff --check`
- Repository search confirms no Option+R polish action, runtime, provider task,
  candidate type, or user-facing copy remains.

## Docs Absorbed By

- [Architecture](../doc/architecture.plan.md)
- [Interfaces](../doc/interfaces.plan.md)
- [Input actions source note](../doc/src/Sources/KnowTypeInputMethod/InputActions.plan.md)
- [Provider prompt source note](../doc/src/Sources/KnowTypeProviders/PromptBuilder.plan.md)

## Retirement Criteria

Retire this record after the removal has shipped in a release and the strict
locked-prefix boundary has remained stable for one release cycle.
