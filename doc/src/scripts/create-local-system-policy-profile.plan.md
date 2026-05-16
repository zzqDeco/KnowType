# scripts/create-local-system-policy-profile.sh

Generates a local macOS SystemPolicyRule configuration profile for the currently
installed KnowType input-method bundle.

Responsibilities:

- inspect the installed `KnowType.app` bundle;
- read the bundle's designated code requirement with `codesign -dr -`;
- write `dist/KnowTypeLocalSystemPolicy.mobileconfig` unless another output
  path is supplied;
- keep profile installation manual by opening the generated file only when
  `--open` is passed.

This script exists for macOS 15+ local development. `spctl --add` is no longer
supported, while Apple Development-signed input method bundles can be registered
with TIS but still rejected by Gatekeeper execution assessment. The generated
profile is a local testing aid, not a release path.

Release builds should use a Developer ID signed and notarized distribution
instead of this local allow profile.
