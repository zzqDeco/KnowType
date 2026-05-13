import XCTest
@testable import KnowTypeCore

private actor RecordingProvider: LLMProvider {
    nonisolated let providerName = "recording"
    private var recordedRequests: [LLMRequest] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        return LLMResponse(candidates: [
            LLMCandidate(text: "cloud should not be used", confidence: 1.0)
        ])
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

final class CorrectionEngineTests: XCTestCase {
    func testPinyinCorrectionProducesAccuratePrefixCandidates() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "wo jue de zhege fagnan", locale: .zhCN)
        )

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
        XCTAssertTrue(candidates.map(\.text).contains("我觉得这个方法"))
        XCTAssertTrue(candidates.map(\.text).contains("我觉得这个方向"))
        XCTAssertGreaterThanOrEqual(candidates.count, 5)
    }

    func testCompactPinyinCorrectionHandlesTypingWithoutSpaces() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "wojuedezhegefagnan", locale: .zhCN)
        )

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
    }

    func testEnglishCorrectionPreservesSentenceShape() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "I thikn this approch", locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, "I think this approach")
    }

    func testMixedInputProtectsTechnicalTokens() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "zhege api latnecy youdian gao", locale: .mixed)
        )

        XCTAssertEqual(candidates.first?.text, "这个 API latency 有点高")
    }

    func testTechnicalTokensArePreserved() async {
        let raw = "API JSON macOS InputMethodKit snake_case camelCase"
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: raw, locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, raw)
    }

    func testLevelZeroInputsAreNotCorrected() async {
        let engine = CorrectionEngine()
        let path = "/Users/zq/project/KnowType"
        let candidates = await engine.correct(InputContext(rawInput: path, locale: .mixed))

        XCTAssertEqual(candidates.first?.text, path)
        XCTAssertEqual(candidates.first?.source, "local-protection")
        XCTAssertEqual(candidates.first?.correctionLevel, CorrectionLevel.none)
    }

    func testLevelZeroContentClassesRequireNoCorrection() {
        let protectedInputs = [
            "https://example.com/search?q=KnowType",
            "example.com/path?q=token",
            "go.dev/doc",
            "visit example.com",
            "send to go.dev",
            "192.168.1.1",
            "localhost:3000",
            "127.0.0.1:8080",
            "api.local:8080",
            "service.internal",
            "example.sh",
            "open https://example.com/search?q=KnowType",
            "open api.local:8080",
            "support@example.com",
            "send this to support@example.com",
            "/Users/zq/project/KnowType",
            "open /Users/zq/project/KnowType",
            "~/Library/Input Methods",
            "git status --short",
            "git config user.email",
            "git stash",
            "docker ps",
            "docker login",
            "kubectl get pods",
            "brew install foo",
            "pnpm install",
            "npm install",
            "curl https://example.com",
            "curl example.com",
            "curl staging",
            "ssh production-box",
            "ssh prod",
            "ssh user@prod",
            "> docker ps",
            "$ docker ps",
            "cat ./Package.swift",
            "cat Package.swift",
            "vim secrets.txt",
            "rm README.md",
            "sudo rm README.md",
            "sudo -E rm README.md",
            "sudo -u deploy git pull",
            "cp .env backup.env",
            "touch /tmp/knowtype",
            "docker ps | rg api",
            "git status&&echo ok",
            "docker ps|rg api",
            "swift test>test.log",
            "swift test > test.log",
            "swift test",
            "go test ./...",
            "make build",
            "pwd",
            "echo $GITHUB_TOKEN",
            "unset API_KEY",
            "env",
            "export PATH=/usr/local/bin:$PATH",
            "source .env",
            "source .env.local",
            "source .env.production",
            "source ./scripts/env.sh",
            "python main.py",
            "python my-script.py",
            "node server.js",
            "node build-prod.js",
            "GITHUB_TOKEN=secret npm publish",
            "API_KEY=secret curl example.com",
            "let appBundleID = context.appBundleID",
            "import Foundation",
            "snake_case",
            "camelCase"
        ]

        for input in protectedInputs {
            XCTAssertTrue(
                TextProtection.requiresNoCorrection(input),
                "\(input) should be Level 0"
            )
        }
    }

    func testProseThatLooksCommandAdjacentStillCorrects() async {
        let proseInputs = [
            "go to market plan",
            "make this easier",
            "make sure this works",
            "make changes later",
            "> I thikn this",
            "$ I thikn this",
            "cat is cute",
            "touch base later",
            "brew coffee",
            "I thikn A > B",
            "price is < expected",
            "I thikn we should import data",
            "let me know the plan",
            "import data",
            "export data later",
            "source material",
            "I thikn camelCase naming works",
            "I thikn snake_case naming works"
        ]

        for input in proseInputs {
            XCTAssertFalse(
                TextProtection.requiresNoCorrection(input),
                "\(input) should not be Level 0"
            )
        }

        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "I thikn A > B", locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, "I think a > b")
        XCTAssertNotEqual(candidates.first?.source, "local-protection")
    }

    func testProseWithCodeTokensStillCorrectsWhilePreservingTokens() async {
        let engine = CorrectionEngine()
        let camelCandidates = await engine.correct(
            InputContext(rawInput: "I thikn camelCase naming works", locale: .enUS)
        )
        let snakeCandidates = await engine.correct(
            InputContext(rawInput: "I thikn snake_case naming works", locale: .enUS)
        )

        XCTAssertEqual(camelCandidates.first?.text, "I think camelCase naming works")
        XCTAssertNotEqual(camelCandidates.first?.source, "local-protection")
        XCTAssertEqual(camelCandidates.first?.protectedRanges.first?.reason, "camelCase")
        XCTAssertEqual(snakeCandidates.first?.text, "I think snake_case naming works")
        XCTAssertNotEqual(snakeCandidates.first?.source, "local-protection")
        XCTAssertEqual(snakeCandidates.first?.protectedRanges.first?.reason, "snake_case")
    }

    func testProtectedAppBundleIDsRequireNoCorrection() {
        let protectedApps = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.googlecode.iterm2.beta",
            "com.apple.dt.Xcode"
        ]

        for bundleID in protectedApps {
            XCTAssertTrue(
                TextProtection.requiresNoCorrection("wo jue de zhege fagnan", appBundleID: bundleID),
                "\(bundleID) should be Level 0"
            )
        }
    }

    func testLevelZeroCorrectionDoesNotCallProvider() async {
        let provider = RecordingProvider()
        let engine = CorrectionEngine(cloudProvider: provider)

        let candidates = await engine.correct(
            InputContext(rawInput: "git status --short", locale: .mixed)
        )
        let requests = await provider.requests

        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(candidates.first?.text, "git status --short")
        XCTAssertEqual(candidates.first?.source, "local-protection")
    }

    func testEmbeddedProtectedContentDoesNotCallProvider() async {
        let provider = RecordingProvider()
        let engine = CorrectionEngine(cloudProvider: provider)

        let candidates = await engine.correct(
            InputContext(rawInput: "open https://example.com/path?q=KnowType", locale: .mixed)
        )
        let requests = await provider.requests

        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(candidates.first?.text, "open https://example.com/path?q=KnowType")
        XCTAssertEqual(candidates.first?.source, "local-protection")
        XCTAssertEqual(candidates.first?.protectedRanges.first?.reason, "url")
    }

    func testBareDomainsAndLocalEndpointsAreProtectedRanges() {
        let examples = [
            ("visit example.com", "example.com"),
            ("send to go.dev", "go.dev"),
            ("open localhost:3000", "localhost:3000"),
            ("connect 127.0.0.1:8080", "127.0.0.1:8080"),
            ("router 192.168.1.1", "192.168.1.1"),
            ("open api.local:8080", "api.local:8080"),
            ("check service.internal", "service.internal"),
            ("run example.sh", "example.sh")
        ]

        for (input, protectedText) in examples {
            let ranges = TextProtection.detectProtectedRanges(in: input)
            let protectedRanges = ranges.filter { $0.reason == "url" }
            let matchedTexts = protectedRanges.map { range in
                let start = input.index(input.startIndex, offsetBy: range.start)
                let end = input.index(start, offsetBy: range.length)
                return String(input[start..<end])
            }

            XCTAssertTrue(
                matchedTexts.contains(protectedText),
                "\(input) should protect \(protectedText) as a URL-like range"
            )
        }
    }
}
