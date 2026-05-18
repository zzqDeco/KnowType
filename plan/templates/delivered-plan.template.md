# <Delivered Plan Title>

Use this template when converting an active plan into a short delivered record.
Move stable behavior into `doc/` first, then keep only the implementation record
that is still useful for release notes or future archaeology.

## Delivered Behavior

- Summarize the behavior that shipped.
- Link to the current-state docs that now own the contract.

## Verification

- List the tests, scripts, CI checks, or manual acceptance evidence used when
  the work landed.

## Docs Absorbed By

- Link to `doc/` and `doc/src/` pages that now describe the stable behavior.

## Retirement Criteria

- State when this plan can be removed from `plan/`.
- Prefer retiring once the behavior has been stable and indexed in current docs.
