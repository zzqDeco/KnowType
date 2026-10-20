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
  `snake_case` segments still keep normal token protection, while callable
  dotted expressions such as `console.log("x")` and `System.out.println()`
  remain under Level 0 code-like protection).
- `.bar` is a delegated TLD, not a blanket code suffix. Bare hosts such as
  `nic.bar`, `cocktail.bar`, and their subdomains match `reason: "url"` and
  trigger Level 0 both alone and in prose. Matching is case-insensitive;
  existing path, query-after-path, and port coverage is unchanged.
- Ambiguous, unschemed, pathless, portless `.bar` inputs retain the existing
  first-label code-prefix filter: `foo.bar`, `self.bar`, and `user.bar` are
  not URL ranges. A following `(`, including after whitespace, also keeps
  `nic.bar()` and `cocktail.bar ()` under code-like rather than URL protection.
  Explicit schemes, `www.`, paths, and ports retain their existing URL
  precedence, including `https://foo.bar` and `foo.bar/menu?lang=en`.
- This is a lexical policy, not a DNS or intent check. It favors a domain
  interpretation for an otherwise unrecognized `venue.bar` property, but a
  code interpretation for real hosts with known code prefixes or prose such
  as `nic.bar (details)`. No host-specific exception, runtime network lookup,
  or exhaustive TLD registry is used.
- URL classification preserves the unchanged local-correction fallback and
  its protected-range metadata for context consumers. It does not establish
  that any cloud request occurred or alter the real-time AI gate.
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
  - Bare `.bar` hosts, URL-range offsets, standalone/prose Level 0 routing,
    local-candidate metadata, explicit URL precedence, and dotted-call
    disambiguation are covered in `KnowTypeCoreTests.swift`.
- `CorrectionEngineTests`
- `PrefixContinuationEngineTests`
- `MVPAcceptanceTests`
