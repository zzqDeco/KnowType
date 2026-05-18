# scripts/install-inputmethod.sh

## Responsibility

Installs the locally built KnowType input method bundle into
`~/Library/Input Methods/KnowType.app`.

## Boundaries

- The script copies and prepares the local development bundle.
- It does not prove target-app typing behavior; manual acceptance still must
  type in real host apps.

## Behavior Notes

- The default path avoids unnecessary mutating helper registration where the
  installed bundle can activate itself.
- macOS 15 local policy issues may still require the SystemPolicyRule profile
  flow before selection works reliably.

## Tests

- `scripts/smoke-inputmethod-install.sh`
- Manual `doc/mvp-acceptance.plan.md` install gate
