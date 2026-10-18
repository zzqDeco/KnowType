# TextProtection

## Responsibility

`TextProtection` owns Level 0 correction-protection detection and secret-like
credential detection for cloud AI hard blocks.

## Boundaries

- It returns protection policy; it does not build candidate panel rows or send
  provider requests.
- Host-app integration details stay in `KnowTypeInputMethod`.

## Behavior Notes

- Level 0 correction-protection inputs include URLs, emails, paths,
  command-like text, code-like snippets, and protected app contexts such as
  Terminal, iTerm, and Xcode. These rules keep correction from rewriting text
  that should usually commit unchanged.
- Unschemed bare-domain URL detection retains coverage across general ASCII TLDs
  (such as `.eu`, `.name`, `.aero`), Punycode IDN suffixes (`xn--...`), and
  local/reserved suffixes (`local`, `lan`, `internal`, `test`, `example`,
  `invalid`, `localhost`), while disambiguating and excluding unschemed,
  pathless, portless dotted code identifiers and prose mistakes such as
  `foo.bar`, `user.name`, `self.coordinator`, `System.out.println`,
  `com.apple.Xcode`, and `hello.world` so they do not falsely match
  `reason: "url"` or trigger Level 0 protection (inner `camelCase` and
  `snake_case` segments still keep normal token protection).
- Real-time cloud AI recommendation uses `containsSecretLikeContent` as its
  only hard block. Normal technical text, commands, paths, URLs, and protected
  app contexts do not directly produce `AI 已禁用`.
- Secret-like detection covers credential-shaped tokens, bearer headers, JWTs,
  PEM private keys, credential assignments, and sensitive URL query values.
- Protection and secret-like pattern matching uses cached
  `NSRegularExpression` objects so hot-path privacy gates do not repeatedly
  compile the same expressions.
- Technical-token preservation is separate from Level 0 routing; mixed prose may
  preserve tokens while still being provider-eligible.

## Tests

- `KnowTypeCoreTests`
- `CorrectionEngineTests`
- `PrefixContinuationEngineTests`
- `MVPAcceptanceTests`
