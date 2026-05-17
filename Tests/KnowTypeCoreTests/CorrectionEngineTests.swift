import XCTest
@testable import KnowTypeCore

private actor RecordingProvider: LLMProvider {
    nonisolated let providerName = "recording"
    private let responseCandidates: [LLMCandidate]
    private var recordedRequests: [LLMRequest] = []

    init(
        responseCandidates: [LLMCandidate] = [
            LLMCandidate(text: "cloud should not be used", confidence: 1.0)
        ]
    ) {
        self.responseCandidates = responseCandidates
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        return LLMResponse(candidates: responseCandidates)
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

    func testUserSelectionHistoryBoostsLocalPrefixRanking() async {
        let engine = CorrectionEngine()

        let defaultCandidates = await engine.correct(
            InputContext(rawInput: "fangan", locale: .zhCN)
        )
        let boostedCandidates = await engine.correct(
            InputContext(
                rawInput: "fangan",
                locale: .zhCN,
                userSelectionHistory: ["方法"]
            )
        )

        XCTAssertEqual(defaultCandidates.first?.text, "方案")
        XCTAssertEqual(boostedCandidates.first?.text, "方法")
        XCTAssertTrue(boostedCandidates.map(\.text).contains("方案"))
    }

    func testProviderCorrectionDoesNotApplySelectionHistoryTwice() async {
        let provider = RecordingProvider(responseCandidates: [])
        let engine = CorrectionEngine(cloudProvider: provider)

        let candidates = await engine.correct(
            InputContext(
                rawInput: "fangan",
                locale: .zhCN,
                userSelectionHistory: ["思路"]
            )
        )

        XCTAssertEqual(candidates.first?.text, "方案")
        XCTAssertTrue(candidates.map(\.text).contains("思路"))
    }

    func testChinesePinyinCorrectionDecodesCapitalizedInitialToken() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "Wo jue de zhege fagnan", locale: .zhCN)
        )

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
    }

    func testCompactPinyinCorrectionHandlesTypingWithoutSpaces() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "wojuedezhegefagnan", locale: .zhCN)
        )

        XCTAssertEqual(candidates.first?.text, "我觉得这个方案")
    }

    func testCompactPinyinCorrectionStillAsksConfiguredProvider() async {
        let provider = RecordingProvider()
        let engine = CorrectionEngine(cloudProvider: provider)

        _ = await engine.correct(
            InputContext(rawInput: "wojuedezhegefagnan", locale: .zhCN)
        )

        let requests = await provider.requests
        XCTAssertEqual(requests.first?.task, .correction)
        XCTAssertEqual(requests.first?.rawInput, "wojuedezhegefagnan")
    }

    func testShortInitialAbbreviationsStayLocalAndDoNotCallProvider() async {
        let examples = [
            ("wsm", "为什么"),
            ("sm", "什么"),
            ("zmb", "怎么办")
        ]

        for (raw, expected) in examples {
            let provider = RecordingProvider()
            let engine = CorrectionEngine(cloudProvider: provider)
            let candidates = await engine.correct(InputContext(rawInput: raw, locale: .zhCN))
            let requests = await provider.requests

            XCTAssertEqual(candidates.first?.text, expected)
            XCTAssertTrue(requests.isEmpty, "\(raw) should not use cloud correction")
        }
    }

    func testUnknownPinyinInitialCompositionCanAskProvider() async {
        let provider = RecordingProvider()
        let engine = CorrectionEngine(cloudProvider: provider)

        _ = await engine.correct(InputContext(rawInput: "wzm", locale: .zhCN))

        let requests = await provider.requests
        XCTAssertEqual(requests.first?.task, .correction)
        XCTAssertEqual(requests.first?.rawInput, "wzm")
    }

    func testUnknownPinyinInitialCompositionWithYCanAskProvider() async {
        let examples = ["wym", "wyx"]

        for raw in examples {
            let provider = RecordingProvider()
            let engine = CorrectionEngine(cloudProvider: provider)

            _ = await engine.correct(InputContext(rawInput: raw, locale: .zhCN))

            let requests = await provider.requests
            XCTAssertEqual(requests.first?.task, .correction, "\(raw) should use pinyin cloud fallback")
            XCTAssertEqual(requests.first?.rawInput, raw)
        }
    }

    func testPinyinCompletionProviderCandidateRanksAheadOfRawIdentity() async {
        let provider = RecordingProvider(responseCandidates: [
            LLMCandidate(text: "我怎么", confidence: 0.72)
        ])
        let engine = CorrectionEngine(cloudProvider: provider)

        let candidates = await engine.correct(InputContext(rawInput: "wzm", locale: .zhCN))

        XCTAssertEqual(candidates.first?.text, "我怎么")
        XCTAssertEqual(candidates.first?.source, "recording")
        XCTAssertTrue(candidates.map(\.text).contains("wzm"))
    }

    func testAdditionalLocalLexiconCandidateDoesNotTriggerPinyinProviderFallback() async {
        let provider = RecordingProvider()
        let traditionalInputEngine = TraditionalInputEngine(additionalLexiconEntries: [
            TraditionalInputLexiconEntry(
                pinyin: ["ce", "shi", "ci"],
                outputs: [TraditionalInputLexiconOutput(text: "测试词", confidence: 0.995)]
            )
        ])
        let engine = CorrectionEngine(
            cloudProvider: provider,
            traditionalInputEngine: traditionalInputEngine
        )

        let candidates = await engine.correct(InputContext(rawInput: "ceshici", locale: .zhCN))
        let requests = await provider.requests

        XCTAssertEqual(candidates.first?.text, "测试词")
        XCTAssertTrue(requests.isEmpty)
    }

    func testTechnicalTokensAndEnglishWordsDoNotTriggerPinyinProviderFallback() async {
        let examples = [
            "css",
            "CDN",
            "gpt",
            "HTTP",
            "llm",
            "npm",
            "PDF",
            "ssh",
            "TCP",
            "by",
            "cry",
            "dry",
            "fly",
            "gym",
            "my",
            "sky",
            "spy",
            "sync",
            "try",
            "why",
            "change",
            "shopping",
            "testing",
            "engineering",
            "going",
            "sharing",
            "english"
        ]

        for raw in examples {
            let provider = RecordingProvider()
            let engine = CorrectionEngine(cloudProvider: provider)

            _ = await engine.correct(InputContext(rawInput: raw, locale: .zhCN))

            let requests = await provider.requests
            XCTAssertTrue(requests.isEmpty, "\(raw) should not use cloud correction")
        }
    }

    func testEnglishCorrectionPreservesSentenceShape() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "I thikn this approch", locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, "I think this approach")
    }

    func testEnglishCorrectionChecksCapitalizedSentenceInitialTypo() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "Thikn this approch", locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, "Think this approach")
    }

    func testEnglishLocaleDoesNotDecodeLowercasePinyinBeforeSpellcheck() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "I thikn xiang", locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, "I think xiang")
        XCTAssertEqual(candidates.first?.source, "local-spellcheck")
        XCTAssertFalse(candidates.map(\.text).contains { $0.contains("想") })
    }

    func testEnglishNameLikePinyinIsNotTranslatedBeforeSpellcheck() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "I thikn Xiang", locale: .enUS)
        )

        XCTAssertEqual(candidates.first?.text, "I think Xiang")
    }

    func testMixedInputProtectsTechnicalTokens() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "zhege api latnecy youdian gao", locale: .mixed)
        )

        XCTAssertEqual(candidates.first?.text, "这个 API latency 有点高")
    }

    func testNormalizedMixedInputDoesNotExposeShiftedRawRanges() async {
        let engine = CorrectionEngine()
        let candidates = await engine.correct(
            InputContext(rawInput: "zhege api latnecy youdian gao", locale: .mixed)
        )

        let candidate = candidates.first { $0.text == "这个 API latency 有点高" }

        XCTAssertNotNil(candidate)
        XCTAssertNil(candidate?.rawRange)
        XCTAssertEqual(candidate?.segments, [])
    }

    func testTechnicalTokensArePreserved() async {
        let raw = "API JSON CSS GPT LLM npm SDK SSH macOS InputMethodKit snake_case camelCase"
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
