# Tighten TextProtection Bare-Domain URL Regex

## Delivered Behavior

- Tightened unschemed bare-domain URL detection in `TextProtection` so valid
  bare domains—including general ASCII TLDs (`.com`, `.cn`, `.eu`, `.name`,
  `.aero`, etc.), Punycode IDN TLDs (`xn--...`), and local/reserved suffixes
  (`local`, `lan`, `internal`, `localhost`)—continue to match `reason: "url"`
  and trigger Level 0 protection without restricting URLs to a tiny hardcoded
  TLD shortlist.
- Added dotted identifier/prose disambiguation (`isLikelyDottedIdentifierOrProseToken`)
  and boundary guards so unschemed, pathless, portless code identifiers and
  prose mistakes such as `foo.bar`, `user.name`, `self.coordinator`,
  `System.out.println`, `com.apple.Xcode`, and `hello.world` do not match
  `reason: "url"` or trigger `TextProtection.requiresNoCorrection`, while
  preserving normal token-level protection for inner `camelCase` and
  `snake_case` tokens.
- Current-state behavior is documented in
  [`doc/src/Sources/KnowTypeCore/TextProtection.plan.md`](../doc/src/Sources/KnowTypeCore/TextProtection.plan.md).

## Verification

- `swift test --filter KnowTypeCoreTests`
  - `KnowTypeCoreTests.testRecognizedBareDomainURLsMatchURLReasonAndRequireNoCorrection`
  - `KnowTypeCoreTests.testDottedCodeIdentifiersAndProseMistakesDoNotMatchURLOrTriggerLevelZeroProtection`
  - `KnowTypeCoreTests.testDottedIdentifiersPreserveInnerCamelCaseAndSnakeCaseTokensWithoutLevelZero`
  - Existing `CorrectionEngineTests` and `PrefixContinuationEngineTests` suites.

## Docs Absorbed By

- [`doc/src/Sources/KnowTypeCore/TextProtection.plan.md`](../doc/src/Sources/KnowTypeCore/TextProtection.plan.md)

## Retirement Criteria

- Retire this delivered plan once the tightened bare-domain URL protection
  behavior is stable and indexed in `doc/src/README.md` and `plan/README.md`.
