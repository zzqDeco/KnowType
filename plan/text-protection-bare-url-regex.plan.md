# Tighten TextProtection Bare-Domain URL Regex

## Delivered Behavior

- Tightened unschemed bare-domain URL matching in `TextProtection` so a dotted
  ASCII token without `http://`, `https://`, or `www.` only matches
  `reason: "url"` and triggers Level 0 protection when its final domain label is
  a recognized TLD (such as `com`, `cn`, `org`, `net`, `edu`, `gov`, `io`, `co`,
  `ai`, `dev`, `app`, `sh`, `local`, `lan`, `internal`, `localhost`, etc.) and is
  not followed by another dotted domain label.
- Prevented dotted code identifiers and prose mistakes such as `foo.bar`,
  `user.name`, `self.coordinator`, `System.out.println`, and `hello.world` from
  matching `reason: "url"` or triggering `TextProtection.requiresNoCorrection`,
  while preserving normal token-level protection for inner `camelCase` and
  `snake_case` tokens.
- Current-state behavior is documented in
  [`doc/src/Sources/KnowTypeCore/TextProtection.swift.plan.md`](../doc/src/Sources/KnowTypeCore/TextProtection.swift.plan.md).

## Verification

- `swift test --filter KnowTypeCoreTests`
  - `KnowTypeCoreTests.testRecognizedBareDomainURLsMatchURLReasonAndRequireNoCorrection`
  - `KnowTypeCoreTests.testDottedCodeIdentifiersAndProseMistakesDoNotMatchURLOrTriggerLevelZeroProtection`
  - `KnowTypeCoreTests.testDottedIdentifiersPreserveInnerCamelCaseAndSnakeCaseTokensWithoutLevelZero`
  - Existing `CorrectionEngineTests` and `PrefixContinuationEngineTests` suites.

## Docs Absorbed By

- [`doc/src/Sources/KnowTypeCore/TextProtection.swift.plan.md`](../doc/src/Sources/KnowTypeCore/TextProtection.swift.plan.md)

## Retirement Criteria

- Retire this delivered plan once the tightened bare-domain URL protection
  behavior is stable and indexed in `doc/src/README.md` and `plan/README.md`.
