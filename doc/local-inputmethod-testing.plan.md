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
- `TISSelectInputSource` can report success inside a helper-local context.
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
./scripts/select-inputmethod.sh --require-selected
./scripts/diagnose-inputmethod.sh --strict --logs --log-lookback 10m
```

Remove the profile after local testing unless this specific Apple Development
build should remain allowed on the machine.

## Acceptance Rule

Do not accept a typing result just because Chinese text appears. Apple Pinyin
can produce many of the same phrases. A local acceptance run must first confirm
that the active app is using KnowType, then type a real probe.

Useful evidence:

- the input menu shows `KnowType`;
- `AppleSelectedInputSources` contains
  `com.knowtype.inputmethod.KnowType.Mode`;
- KnowType logs appear while typing, not only during installation;
- `Gatekeeper assessment accepts the installed bundle` appears in diagnostics.

If the active app remains on Apple Pinyin after the profile is installed, log
out and back in to clear stale Text Input Source cache entries before repeating
the install and selection checks.

The bundle metadata should also match IMKit's background input-method shape:
`LSBackgroundOnly=true`, no foreground `LSUIElement`, and `zh-Hans` in the
character repertoire so System Settings can classify the input method under
Simplified Chinese.
