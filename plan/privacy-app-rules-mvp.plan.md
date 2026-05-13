# Privacy App Rules MVP

## Scope

Make Level 0 privacy behavior explicit in `KnowTypeCore` and pass app bundle identity through the input-method pipeline without adding provider-layer rules.

## Implemented Rules

- URLs, emails, file paths, command-like input, and code-like tokens are no-correction contexts.
- Terminal, iTerm2, and Xcode bundle IDs are no-correction contexts.
- Level 0 correction returns the original text from local protection.
- Level 0 continuation returns no candidates, so protected input commits unchanged and never calls a cloud provider.

## Verification

- Core tests cover protected app bundle IDs, technical token preservation, protected content classes, and provider-not-called behavior.
- Input-method tests cover app bundle propagation, continuation clearing, and direct pipeline provider isolation for Level 0.
