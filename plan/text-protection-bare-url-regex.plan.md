# TextProtection Bare-Domain URL Protection

Status: Active

## Summary

- Restore `.bar` domain URL/Level 0 protection without undoing Issue #227's
  dotted-code/prose disambiguation. The base suffix filter rejects `nic.bar`
  and `visit nic.bar` even though [IANA lists `.bar` and `nic.bar`](https://www.iana.org/domains/root/db/bar.html).
- This follow-up is based on `4e6a5f82fe4903e069f4d4e5a98d6bc2474c3b91`;
  candidate validation and integration belong to the coordinator.

## Scope

- Change only `Sources/KnowTypeCore/TextProtection.swift`, its focused tests
  in `Tests/KnowTypeCoreTests/KnowTypeCoreTests.swift`, the existing
  [source note](../doc/src/Sources/KnowTypeCore/TextProtection.plan.md), and
  this plan.
- No provider, AI-gate, input-method, public API, schema, runtime DNS/TLD
  lookup, or exhaustive TLD registry changes. Classification/local fallback
  and protected-range context are the contract; cloud leakage is not an
  observed result of this work.
- Shared READMEs, architecture/interfaces, and indexes remain unchanged for
  the coordinator's serial integration update.

## Implementation

- Keep the existing bare-domain regex, general ASCII/Punycode coverage,
  local/reserved suffix handling, and unambiguous-TLD precedence.
- Remove `bar` from blanket code-suffix rejection, but not into the
  unambiguous-TLD set: existing code prefixes still exclude `foo.bar`,
  `self.bar`, `user.bar`, and `foo.com.bar` without excluding ordinary
  `.bar` hosts such as `nic.bar` and `cocktail.bar`.
- Pass the text following each matched range into the private dotted-token
  filter. For an ambiguous bare `.bar` candidate, an immediately following
  argument list (optional whitespace before `(`) keeps `nic.bar()` and
  `cocktail.bar ()` as code-like expressions, not URL ranges. Other suffix
  decisions are unchanged.
- Preserve explicit-scheme, `www.`, path, and port precedence; for example,
  `https://foo.bar`, `foo.bar:443`, and `foo.bar/menu?lang=en` remain URLs.
- Keep local fallback text unchanged with `source: "local-protection"`,
  Level 0, and complete URL-range metadata for standalone and prose inputs.

## Test Plan

- Local validation is limited to static reading and `git diff --check`.
  No local builds, tests, repro programs, performance scripts, host-app
  automation, or input-method installation are permitted for this slice.
- CI selector: `.github/workflows/ci.yml`, job `test` (`Swift build and test`)
  on the exact candidate or integrated head.
- Focused CI command: `swift test --filter KnowTypeCoreTests`.
  - `testRecognizedBareDomainURLsMatchURLReasonAndRequireNoCorrection`
    adds bare `nic.bar`, `cocktail.bar`, case, subdomain, hyphenated-host,
    port, and path/query fixtures, alone and in prose.
  - `testBarDomainsAndExplicitDottedURLsKeepLocalProtection` checks unchanged
    local candidates and complete URL-range offsets, including explicit URL
    markers overriding code-like host names.
  - Existing dotted identifier/token tests retain negative `foo.bar`,
    `self.coordinator`, `user.name`, `System.out`, and `config.json` cases;
    dotted calls with and without argument-list whitespace remain code-like.
- Red/green recommendation in CI: run the updated focused tests against the
  base implementation before the candidate implementation. Bare `nic.bar`
  and `cocktail.bar`, including their prose forms, must expose the base
  regression. This expectation is from static inspection, not a local run.
- Required CI completion: `swift build` and full `swift test`, including
  `CorrectionEngineTests` and `PrefixContinuationEngineTests`. Existing
  workflow smoke/performance steps remain owned by CI and the coordinator.

## Assumptions

- Lexical ambiguity is intentional: a real `user.bar` host stays excluded
  without URL markers, while an unrecognized `venue.bar` property can look
  like a domain. `nic.bar (details)` is treated as callable syntax; an
  explicit scheme disambiguates it as a URL.
- No fixture asserts DNS registration or reachability for arbitrary
  domain-shaped hosts. Only `.bar` delegation and the `nic.bar` registry
  example are sourced from IANA.
- CI results are pending; this record remains Active until the coordinator
  validates and integrates the candidate.
