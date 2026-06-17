# Local Input Method Testing

This document covers the local macOS acceptance path for Apple Development
builds. It is intentionally separate from the README because these details are
developer-machine diagnostics, not product presentation.

## Current macOS 15 Constraint

On macOS 15+, `spctl --add` no longer adds local Gatekeeper allow rules. Apple
now points rule changes at configuration profiles. A KnowType bundle can pass
`codesign --verify`, register with TIS, and still be rejected by Gatekeeper:

```text
GatekeeperPolicyScanError Code=-67018
Code did not match any currently allowed policy
```

When this happens, Text Input Source selection can look inconsistent:

- `knowtype-inputsource-tool` can see KnowType as registered, enabled, and
  select-capable.
- `TISSelectInputSource` can report success in an app or diagnostic context.
- `com.apple.HIToolbox` may still keep `AppleSelectedInputSources` on Apple
  Pinyin.
- A real target app may continue typing through Apple Pinyin instead of
  KnowType.

That is a system policy and selection-chain problem, not a pinyin engine
problem.

## Local Allow Profile

For local Apple Development testing, generate a device SystemPolicyRule profile
from the currently installed bundle:

```bash
./scripts/create-local-system-policy-profile.sh --open
```

The script reads the installed bundle's designated code requirement and writes:

```text
dist/KnowTypeLocalSystemPolicy.mobileconfig
```

macOS no longer installs configuration profiles from the `profiles` CLI. The
generated profile must be installed through System Settings. After installing
it, verify:

```bash
spctl --assess --type execute --verbose=4 "$HOME/Library/Input Methods/KnowType.app"
./scripts/diagnose-inputmethod.sh --strict --logs --log-lookback 10m
./scripts/select-inputmethod.sh --require-selected --no-diagnose
```

For a repeatable acceptance pass, run the harness after installing the bundle
and any required local policy profile:

```bash
./scripts/accept-inputmethod-local.sh --strict --print-checklist
```

Use `--install` only when the harness should rebuild and copy the bundle. Use
`--select` only after the target text app is active, because selection is scoped
to the active text input context.

Remove the profile after local testing unless this specific Apple Development
build should remain allowed on the machine.

## Acceptance Rule

Do not accept a typing result just because Chinese text appears. Apple Pinyin
can produce many of the same phrases. A local acceptance run must first confirm
that the active app is using KnowType, then type a real probe.

Useful evidence:

- the input menu shows `KnowType`;
- `AppleSelectedInputSources` contains
  `com.knowtype.inputmethod.KnowType`;
- KnowType logs appear while typing, not only during installation;
- `Gatekeeper assessment accepts the installed bundle` appears in diagnostics.

If macOS shows an authorization prompt asking whether to allow `知键` to enable
`KnowType`, click Allow before treating any typing probe as KnowType behavior.

If the active app remains on Apple Pinyin after the profile is installed, run
the local repair script before falling back to logout:

```bash
./scripts/repair-inputmethod-selection.sh
```

The script uses the input-source helper to disable visible legacy `.Mode` TIS
rows and unregister stale LaunchServices records for older KnowType build paths,
rewrites only KnowType rows in protected input-source preferences so HIToolbox
and `com.apple.inputsources` point at the single visible `.Hans` mode, restarts
Text Input menu agents, and requests `.Hans` selection through TIS without
launching the input-method host. If diagnostics still show stale `.Mode` rows,
non-selectable parent preference rows, or missing `.Hans` rows, remove and
re-add KnowType in System Settings. If selection still falls back after repair,
log out and back in to clear
session-level Text Input Source state before repeating the install and
selection checks.

The bundle metadata should match mature IMK frontend shape: `LSUIElement=true`,
`LSBackgroundOnly=false`, a compact `TISIconLabels` primary label, and Chinese
script repertoire values such as `Hans`, `Hant`, `Hani`, `Hanb`, and `Han`.
Do not advertise `Latn` in the visible Chinese input source; KnowType can still
pass through English keystrokes internally, but the system input source should
not be classified as an ASCII-capable keyboard layout.
