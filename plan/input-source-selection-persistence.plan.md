# Input Source Selection Persistence

## Goal

Make local input-method acceptance scripts reflect how macOS applies Text Input Source selection to the active text input context.

## Behavior

- `scripts/select-inputmethod.sh --require-selected` verifies KnowType selection inside the same TIS process that requested selection.
- The helper tells developers to activate the target text app before running it.
- The helper labels this as a selection preflight and tells developers to type a real probe in the target app before accepting manual typing.
- The follow-up install diagnostic stays read-only and no longer receives `--require-selected` from the selection helper, because a separate diagnostic process can observe a different app context.
- `scripts/diagnose-inputmethod.sh --require-selected` remains available, but its wording now makes the context limitation explicit.
- `scripts/install-inputmethod.sh` prints the correct manual acceptance order: install, diagnose, activate target app, select.

## Verification

```bash
swift test
swift build
./scripts/install-inputmethod.sh
./scripts/diagnose-inputmethod.sh --strict
./scripts/select-inputmethod.sh --require-selected
# Then type a real probe in the target app, for example nishishei + Space -> 你是谁.
```
