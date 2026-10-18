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
            "example.xn--p1ai"
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

    func testDottedCodeIdentifiersAndProseMistakesDoNotMatchURLOrTriggerLevelZeroProtection() {
        let nonURLDottedTokens = [
            "foo.bar",
            "user.name",
            "self.coordinator",
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
            "System.out.println ()"
        ] {
            XCTAssertFalse(
                TextProtection.detectProtectedRanges(in: dottedCall).contains { $0.reason == "url" },
                "\(dottedCall) should not match reason: \"url\""
            )
            XCTAssertTrue(
                TextProtection.requiresNoCorrection(dottedCall),
                "\(dottedCall) should stay protected as code-like"
            )
        }
    }
}
