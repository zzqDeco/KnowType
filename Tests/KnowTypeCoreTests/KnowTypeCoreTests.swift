import XCTest
@testable import KnowTypeCore

final class KnowTypeCoreTests: XCTestCase {
    func testRecognizedBareDomainURLsMatchURLReasonAndRequireNoCorrection() {
        let bareURLs = [
            "example.com",
            "openai.com/v1/chat",
            "api.deepseek.com:443",
            "knowtype.ai",
            "apple.com.cn",
            "github.io/repo",
            "api.local:8080",
            "service.internal",
            "dev.localhost:3000",
            "localhost",
            "example.eu",
            "example.name",
            "Example.name",
            "Example.academy",
            "self.com",
            "this.dev",
            "super.ai",
            "example.aero",
            "example.xn--p1ai",
            "nic.bar",
            "cocktail.bar",
            "NIC.BAR",
            "events.cocktail.bar",
            "drinks-menu.bar",
            "nic.bar:443",
            "nic.bar/registry?lang=en",
            "cocktail.bar/menu?lang=en"
        ]

        for bareURL in bareURLs {
            let standaloneRanges = TextProtection.detectProtectedRanges(in: bareURL)
            let urlRanges = standaloneRanges.filter { $0.reason == "url" }
            let matchedTexts = urlRanges.map { range in
                let start = bareURL.index(bareURL.startIndex, offsetBy: range.start)
                let end = bareURL.index(start, offsetBy: range.length)
                return String(bareURL[start..<end])
            }

            XCTAssertTrue(
                matchedTexts.contains(bareURL),
                "\(bareURL) should match reason: \"url\""
            )
            XCTAssertTrue(
                TextProtection.requiresNoCorrection(bareURL),
                "\(bareURL) should trigger Level 0 protection"
            )

            let embeddedInput = "visit \(bareURL) now"
            let embeddedRanges = TextProtection.detectProtectedRanges(in: embeddedInput)
            let embeddedURLTexts = embeddedRanges
                .filter { $0.reason == "url" }
                .map { range in
                    let start = embeddedInput.index(embeddedInput.startIndex, offsetBy: range.start)
                    let end = embeddedInput.index(start, offsetBy: range.length)
                    return String(embeddedInput[start..<end])
                }

            XCTAssertTrue(
                embeddedURLTexts.contains(bareURL),
                "\(embeddedInput) should protect \(bareURL) as a URL range"
            )
            XCTAssertTrue(
                TextProtection.requiresNoCorrection(embeddedInput),
                "\(embeddedInput) should trigger Level 0 protection"
            )
        }
    }

    func testBarDomainsAndExplicitDottedURLsKeepLocalProtection() throws {
        let engine = CorrectionEngine()
        let urls = [
            "nic.bar",
            "cocktail.bar",
            "nic.bar/registry?lang=en",
            "cocktail.bar/menu?lang=en",
            "https://foo.bar",
            "https://self.bar",
            "https://self.coordinator",
            "https://user.name",
            "https://System.out",
            "https://config.json",
            "https://cocktail.bar()",
            "www.foo.bar",
            "foo.bar/menu?lang=en",
            "foo.bar:443"
        ]

        for url in urls {
            for prefix in ["", "visit "] {
                let input = prefix + url
                let candidates = engine.localCorrect(InputContext(rawInput: input, locale: .enUS))
                let candidate = try XCTUnwrap(candidates.first, input)

                XCTAssertTrue(TextProtection.requiresNoCorrection(input), input)
                XCTAssertEqual(candidates.count, 1, input)
                XCTAssertEqual(candidate.text, input, input)
                XCTAssertEqual(candidate.source, "local-protection", input)
                XCTAssertEqual(candidate.correctionLevel, CorrectionLevel.none, input)
                XCTAssertTrue(
                    candidate.protectedRanges.contains(
                        ProtectedRange(start: prefix.count, length: url.count, reason: "url")
                    ),
                    "\(input) should retain the complete URL range on the local candidate"
                )
            }
        }
    }

    func testDottedCodeIdentifiersAndProseMistakesDoNotMatchURLOrTriggerLevelZeroProtection() {
        let nonURLDottedTokens = [
            "foo.bar",
            "self.bar",
            "user.bar",
            "bar.bar",
            "user.name",
            "self.coordinator",
            "config.json",
            "cocktail.json",
            "cocktail.coordinator",
            "cocktail.baz",
            "System.out",
            "System.out.println",
            "hello.world",
            "System.in.read",
            "user.id.value",
            "foo.com.bar",
            "com.apple.Xcode"
        ]

        for token in nonURLDottedTokens {
            let standaloneRanges = TextProtection.detectProtectedRanges(in: token)
            XCTAssertFalse(
                standaloneRanges.contains { $0.reason == "url" },
                "\(token) should not match reason: \"url\""
            )
            XCTAssertFalse(
                TextProtection.requiresNoCorrection(token),
                "\(token) should not trigger Level 0 protection"
            )

            let embeddedInput = "check \(token) value"
            let embeddedRanges = TextProtection.detectProtectedRanges(in: embeddedInput)
            XCTAssertFalse(
                embeddedRanges.contains { $0.reason == "url" },
                "\(embeddedInput) should not match reason: \"url\""
            )
            XCTAssertFalse(
                TextProtection.requiresNoCorrection(embeddedInput),
                "\(embeddedInput) should not trigger Level 0 protection"
            )
        }
    }

    func testDottedIdentifiersPreserveInnerCamelCaseAndSnakeCaseTokensWithoutLevelZero() async {
        let camelInput = "self.inputCoordinator"
        let camelRanges = TextProtection.detectProtectedRanges(in: camelInput)
        XCTAssertFalse(camelRanges.contains { $0.reason == "url" })
        XCTAssertEqual(
            camelRanges.filter { $0.reason == "camelCase" },
            [ProtectedRange(start: 5, length: 16, reason: "camelCase")]
        )
        XCTAssertFalse(TextProtection.requiresNoCorrection(camelInput))

        let snakeInput = "user.first_name"
        let snakeRanges = TextProtection.detectProtectedRanges(in: snakeInput)
        XCTAssertFalse(snakeRanges.contains { $0.reason == "url" })
        XCTAssertEqual(
            snakeRanges.filter { $0.reason == "snake_case" },
            [ProtectedRange(start: 5, length: 10, reason: "snake_case")]
        )
        XCTAssertFalse(TextProtection.requiresNoCorrection(snakeInput))

        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "I thikn self.coordinator works", locale: .enUS)
        )
        XCTAssertEqual(candidates.first?.text, "I think self.coordinator works")
        XCTAssertNotEqual(candidates.first?.source, "local-protection")

        for dottedCall in [
            #"console.log("x")"#,
            #"console.log ("x")"#,
            "System.out.println()",
            "System.out.println ()",
            "foo.bar()",
            "foo.bar ()",
            "nic.bar()",
            "nic.bar ()",
            "cocktail.bar()",
            "cocktail.bar ()",
            "cocktail.bar\t()"
        ] {
            for input in [dottedCall, "check \(dottedCall) now"] {
                XCTAssertFalse(
                    TextProtection.detectProtectedRanges(in: input).contains { $0.reason == "url" },
                    "\(input) should not match reason: \"url\""
                )
                XCTAssertTrue(
                    TextProtection.requiresNoCorrection(input),
                    "\(input) should stay protected as code-like"
                )
            }
        }
    }
}
