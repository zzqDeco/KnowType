# TextProtection

## Responsibility

`TextProtection` owns Level 0 protected-input detection and app-context privacy
rules.

## Boundaries

- It returns protection policy; it does not build candidate panel rows or send
  provider requests.
- Host-app integration details stay in `KnowTypeInputMethod`.

## Behavior Notes

- Protected inputs include URLs, emails, paths, command-like text, code-like
  snippets, and protected app contexts such as Terminal, iTerm, and Xcode.
- Level 0 input must not call cloud providers and should commit unchanged by
  default.
- Technical-token preservation is separate from Level 0 routing; mixed prose may
  preserve tokens while still being provider-eligible.

## Tests

- `CorrectionEngineTests`
- `PrefixContinuationEngineTests`
- `MVPAcceptanceTests`
