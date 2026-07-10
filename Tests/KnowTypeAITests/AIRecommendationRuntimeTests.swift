import Foundation
import XCTest
@testable import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

final class AIRecommendationRuntimeTests: XCTestCase {
    func testDefaultHardTimeoutIsTenSeconds() {
        XCTAssertEqual(AIRecommendationRuntime.Defaults.hardTimeoutMilliseconds, 10_000)
    }

    func testDefaultDebounceIsThreeHundredFiftyMilliseconds() {
        XCTAssertEqual(AIRecommendationRuntime.Defaults.debounceMilliseconds, 350)
    }

    func testDiagnosticFormatterPreservesPrefixLength() {
        let fields = OSLogAIRecommendationDiagnosticSink.fields(
            for: AIRecommendationDiagnosticEvent(
                stage: .skippedPrefixTooShort,
                rawLength: 5,
                rawRevision: 7,
                prefixLength: 2,
                providerName: "spark"
            )
        )
        let line = InputDebugDiagnostics.formatLine(category: .ai, fields: fields)

        XCTAssertTrue(line.contains("rawLength=5"))
        XCTAssertTrue(line.contains("rawRevision=7"))
        XCTAssertTrue(line.contains("prefixLength=2"))
        XCTAssertTrue(line.contains("provider=spark"))
    }

    func testLazyDefaultCanDisableProviderDebounceForInputMethodFactoryPath() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "这个方案可以继续推进。", confidence: 0.8)
        ]))
        let loader = SequencedProviderLoader([provider])
        let diagnosticSink = RecordingDiagnosticSink()
        let runtime = LazyDefaultAIRecommendationRuntime(
            providerLoader: { loader.load() },
            diagnosticSink: diagnosticSink,
            debounceMilliseconds: 0
        )

        let state = await runtime.recommendation(
            for: AIRecommendationRequest(rawInput: "zhegefangan", compositionID: 1)
        )

        guard case .ready = state else {
            return XCTFail("expected ready AI recommendation")
        }
        XCTAssertEqual(loader.count, 1)
        let providerRequestCount = await provider.requests.count
        XCTAssertEqual(providerRequestCount, 1)
        XCTAssertFalse(diagnosticSink.events.contains { $0.stage == .debounceStart })
        XCTAssertFalse(diagnosticSink.events.contains { $0.stage == .debounceEnd })
    }

    func testLazyDefaultRecommendationRetriesProviderLoadAfterMissingProvider() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "这个方案可以继续推进。", confidence: 0.8)
        ]))
        let loader = SequencedProviderLoader([nil, provider])
        let providerAvailability = AIRecommendationProviderAvailabilityState()
        let runtime = LazyDefaultAIRecommendationRuntime(
            providerLoader: { loader.load() },
            diagnosticSink: NoopAIRecommendationDiagnosticSink(),
            providerAvailability: providerAvailability
        )
        let request = AIRecommendationRequest(rawInput: "zhegefangan", compositionID: 1)

        XCTAssertEqual(providerAvailability.providerAvailability, .unknown)
        let first = await runtime.recommendation(for: request)
        XCTAssertEqual(providerAvailability.providerAvailability, .unavailable)
        let second = await runtime.recommendation(for: request)
        XCTAssertEqual(providerAvailability.providerAvailability, .available)

        guard case .unavailable(let reason) = first else {
            return XCTFail("expected missing provider on first request")
        }
        XCTAssertEqual(reason, "AI 未配置")
        guard case .ready(let candidate) = second else {
            return XCTFail("expected provider to be loaded on second request")
        }
        XCTAssertEqual(candidate.displayText, "这个方案可以继续推进。")
        XCTAssertEqual(loader.count, 2)
        let providerRequestCount = await provider.requests.count
        XCTAssertEqual(providerRequestCount, 1)
    }

    func testTriggerPolicyAllowsThreeCharacterRawInputWithoutLockedPrefix() {
        let policy = AIRecommendationTriggerPolicy.default

        XCTAssertTrue(policy.decision(rawInput: "api", lockedPrefix: nil).isEligible)
        XCTAssertTrue(policy.decision(rawInput: "json", lockedPrefix: nil).isEligible)
        XCTAssertTrue(policy.decision(rawInput: "zhege", lockedPrefix: nil).isEligible)
        XCTAssertTrue(policy.decision(rawInput: "nihao", lockedPrefix: nil).isEligible)
    }

    func testTriggerPolicyRejectsOneOrTwoCharacterRawInputWithoutLockedPrefix() {
        let policy = AIRecommendationTriggerPolicy.default

        XCTAssertEqual(
            policy.decision(rawInput: "n", lockedPrefix: nil),
            .rejected(.rawTooShort)
        )
        XCTAssertEqual(
            policy.decision(rawInput: "ni", lockedPrefix: nil),
            .rejected(.rawTooShort)
        )
        XCTAssertEqual(
            policy.decision(rawInput: " \n", lockedPrefix: nil),
            .rejected(.rawTooShort)
        )
    }

    func testTriggerPolicyKeepsLockedPrefixThresholdStrict() {
        let policy = AIRecommendationTriggerPolicy.default

        XCTAssertEqual(
            policy.decision(rawInput: "wo", lockedPrefix: "我"),
            .rejected(.prefixTooShort)
        )
        XCTAssertTrue(policy.decision(rawInput: "nihao", lockedPrefix: "你好").isEligible)
        XCTAssertTrue(policy.decision(rawInput: "approach", lockedPrefix: "prefix").isEligible)
    }

    func testLegacyTraditionalCandidateDoesNotUseFirstCandidateHint() {
        let request = AIRecommendationRequest(
            rawInput: "zhegefangan",
            candidateHints: [
                AICandidateHint(text: "这个方案", nativeIndex: 0, pageNumber: 0)
            ],
            compositionID: 1
        )

        XCTAssertEqual(request.traditionalCandidate.text, "")
        XCTAssertEqual(request.traditionalCandidate.source, "raw-input")
    }

    func testRecommendationWithoutLockedPrefixIgnoresCandidateHints() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "这个方案还可以再细化一下。", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let request = AIRecommendationRequest(
            rawInput: "zhege fangan",
            lockedPrefix: nil,
            candidateHints: [
                AICandidateHint(text: "这个方案", nativeIndex: 0, pageNumber: 0, isHighlighted: true),
                AICandidateHint(text: "这个方向", nativeIndex: 1, pageNumber: 0)
            ],
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)
        let requests = await provider.requests

        guard case .ready(let candidate) = state else {
            return XCTFail("expected ready AI recommendation")
        }
        XCTAssertEqual(candidate.prefixText, "")
        XCTAssertNil(candidate.continuationText)
        XCTAssertEqual(candidate.displayText, "这个方案还可以再细化一下。")
        XCTAssertEqual(requests.first?.lockedPrefix, nil)
        XCTAssertEqual(requests.first?.candidateHints, [])
    }

    func testRecommendationCacheIgnoresCandidateHints() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "这个方案还可以再细化一下。", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)

        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "zhegefangan",
                candidateHints: [AICandidateHint(text: "这个方案", nativeIndex: 0, pageNumber: 0)],
                compositionID: 1
            )
        )
        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "zhegefangan",
                candidateHints: [AICandidateHint(text: "这个方向", nativeIndex: 0, pageNumber: 1)],
                compositionID: 1
            )
        )

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.candidateHints, [])
    }

    func testRecommendationDropsCandidateHintsBeforeProviderRequest() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "这个方案还可以再细化一下。", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "zhege url",
            lockedPrefix: nil,
            candidateHints: [
                AICandidateHint(text: "这个方案", nativeIndex: 0, pageNumber: 0),
                AICandidateHint(text: "API_KEY=sk-abcdefghijklmnopqrstuvwxyz", nativeIndex: 1, pageNumber: 0)
            ],
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)
        let requests = await provider.requests

        guard case .ready(let candidate) = state else {
            return XCTFail("expected ready recommendation")
        }
        XCTAssertEqual(candidate.displayText, "这个方案还可以再细化一下。")
        XCTAssertEqual(requests.first?.candidateHints, [])
        XCTAssertFalse(diagnosticSink.events.contains {
            $0.stage == .skippedProtectedText && $0.reason == "secret_hint_filtered"
        })
    }

    func testRecommendationDoesNotDisableForTechnicalTokensOrAppContext() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "can be handled naturally", confidence: 0.82)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let request = AIRecommendationRequest(
            rawInput: "ijustworks",
            lockedPrefix: nil,
            candidateHints: [
                AICandidateHint(text: "InputMethodKit", nativeIndex: 0, pageNumber: 0),
                AICandidateHint(text: "iOS", nativeIndex: 1, pageNumber: 0)
            ],
            appBundleID: "com.apple.dt.Xcode",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)
        let requests = await provider.requests

        guard case .ready(let candidate) = state else {
            return XCTFail("expected provider-backed recommendation")
        }
        XCTAssertEqual(candidate.displayText, "can be handled naturally")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.rawInput, "ijustworks")
        XCTAssertEqual(requests.first?.candidateHints, [])
    }

    func testRecommendationCallsProviderForThreeCharacterRawInputWithoutLockedPrefix() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "API latency 可以继续优化。", confidence: 0.82)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let request = AIRecommendationRequest(
            rawInput: "api",
            lockedPrefix: nil,
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)
        let requests = await provider.requests

        guard case .ready(let candidate) = state else {
            return XCTFail("expected provider-backed recommendation")
        }
        XCTAssertEqual(candidate.displayText, "API latency 可以继续优化。")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.rawInput, "api")
        XCTAssertEqual(requests.first?.candidateHints, [])
    }

    func testRecommendationSkipsTwoCharacterRawInputWithRawTooShortReason() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "你好", confidence: 0.82)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "ni",
            lockedPrefix: nil,
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)
        let requests = await provider.requests

        XCTAssertEqual(state, .ineligible(reason: "AI 无推荐"))
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .skippedPrefixTooShort && $0.reason == "raw_too_short"
        })
    }

    func testShortLockedPrefixDoesNotUseCandidateHintsToBypassCloudThreshold() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "还可以继续推进。", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "wo",
            lockedPrefix: "我",
            candidateHints: [
                AICandidateHint(text: "我觉得这个方案", nativeIndex: 0, pageNumber: 0)
            ],
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)
        let requests = await provider.requests

        XCTAssertEqual(state, .ineligible(reason: "AI 无推荐"))
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .skippedPrefixTooShort && $0.reason == "prefix_too_short"
        })
    }

    func testLockedPrefixWhitespaceIsPreservedInRecommendationDisplayText() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "我觉得这个方案还可以再细化一下。", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let request = AIRecommendationRequest(
            rawInput: "wo juede",
            lockedPrefix: "  我觉得这个方案 ",
            candidateHints: [
                AICandidateHint(text: "我觉得这个方案", nativeIndex: 0, pageNumber: 0)
            ],
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)

        guard case .ready(let candidate) = state else {
            return XCTFail("expected ready AI recommendation")
        }
        XCTAssertEqual(candidate.prefixText, "  我觉得这个方案 ")
        XCTAssertEqual(candidate.continuationText, "还可以再细化一下。")
        XCTAssertEqual(candidate.displayText, "  我觉得这个方案 还可以再细化一下。")
    }

    func testRecommendationRepairPreservesPunctuationAndFinalDisplayText() async {
        let cases: [(
            name: String,
            prefix: String,
            providerText: String,
            continuation: String,
            displayText: String
        )] = [
            ("English comma", "I think", "I think, therefore I am", ", therefore I am", "I think, therefore I am"),
            ("Chinese comma", "我觉得这个方案", "我觉得这个方案，还有空间", "，还有空间", "我觉得这个方案，还有空间"),
            ("period", "This works", "This works. Next step.", ". Next step.", "This works. Next step."),
            ("semicolon", "The result", "The result; however", "; however", "The result; however"),
            ("colon", "结论", "结论：可以推进", "：可以推进", "结论：可以推进"),
            ("exact duplicate", "I think,", "I think,, therefore I am", " therefore I am", "I think, therefore I am"),
            ("suffix only", "I think", ", therefore I am", ", therefore I am", "I think, therefore I am")
        ]

        for testCase in cases {
            let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
                LLMCandidate(text: testCase.providerText, confidence: 0.88)
            ]))
            let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
            let request = AIRecommendationRequest(
                rawInput: "continuation",
                lockedPrefix: testCase.prefix,
                appBundleID: "com.apple.TextEdit",
                compositionID: 1
            )

            let state = await runtime.recommendation(for: request)

            guard case .ready(let candidate) = state else {
                XCTFail("expected ready AI recommendation: \(testCase.name)")
                continue
            }
            XCTAssertEqual(candidate.prefixText, testCase.prefix, testCase.name)
            XCTAssertEqual(candidate.continuationText, testCase.continuation, testCase.name)
            XCTAssertEqual(candidate.displayText, testCase.displayText, testCase.name)
        }
    }

    func testRecommendationRepairCanReturnPunctuationOnlySuffix() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "我觉得这个方案，", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let request = AIRecommendationRequest(
            rawInput: "continuation",
            lockedPrefix: "我觉得这个方案",
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)

        guard case .ready(let candidate) = state else {
            return XCTFail("expected punctuation-only ready recommendation")
        }
        XCTAssertEqual(candidate.continuationText, "，")
        XCTAssertEqual(candidate.displayText, "我觉得这个方案，")
    }

    func testRecommendationRejectsRepeatedPrefixWithOnlyVisualSeparators() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "我觉得这个方案 | ｜", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "continuation",
            lockedPrefix: "我觉得这个方案",
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)

        XCTAssertEqual(state, .ineligible(reason: "AI 无推荐"))
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .sanitizeEmpty && $0.reason == "no_usable_suffix"
        })
    }

    func testRecommendationRejectsPunctuationPrefixedRepeatWithOrWithoutProtocolSeparator() async {
        for providerText in [
            "| ，我觉得这个方案还有问题",
            "，我觉得这个方案还有问题"
        ] {
            let diagnosticSink = RecordingDiagnosticSink()
            let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
                LLMCandidate(text: providerText, confidence: 0.88)
            ]))
            let runtime = AIRecommendationRuntime(
                provider: provider,
                debounceMilliseconds: 0,
                diagnosticSink: diagnosticSink
            )
            let request = AIRecommendationRequest(
                rawInput: "continuation",
                lockedPrefix: "我觉得这个方案",
                appBundleID: "com.apple.TextEdit",
                compositionID: 1
            )

            let state = await runtime.recommendation(for: request)

            XCTAssertEqual(state, .ineligible(reason: "AI 无推荐"), providerText)
            XCTAssertTrue(diagnosticSink.events.contains {
                $0.stage == .sanitizeEmpty && $0.reason == "still_repeats_prefix"
            }, providerText)
        }
    }

    func testRecommendationDiagnosticsRecordSuccessAndCacheHit() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        _ = await runtime.recommendation(for: request)
        _ = await runtime.recommendation(for: request)

        let stages = diagnosticSink.events.map(\.stage)
        XCTAssertTrue(stages.contains(.contextLoaded))
        XCTAssertTrue(stages.contains(.cacheMiss))
        XCTAssertTrue(stages.contains(.providerRequestStart))
        XCTAssertTrue(stages.contains(.providerResponse))
        XCTAssertTrue(stages.contains(.ready))
        XCTAssertTrue(stages.contains(.cacheHit))
        XCTAssertTrue(diagnosticSink.events.allSatisfy { $0.requestID == request.requestID })
        XCTAssertTrue(diagnosticSink.events.allSatisfy { $0.rawLength == "nihao".count })
        XCTAssertTrue(diagnosticSink.events.allSatisfy { $0.prefixLength == "你好".count })
    }

    func testRecommendationSkipsSingleHanPrefixBeforeProviderRequest() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "wo",
            traditionalCandidate: CorrectionCandidate(
                text: "我",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)
        let requests = await provider.requests

        XCTAssertEqual(state, .ineligible(reason: "AI 无推荐"))
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .skippedPrefixTooShort && $0.reason == "prefix_too_short"
        })
    }

    func testRecommendationCancellationDuringDebounceRecordsNewInputReason() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "API latency 可以继续优化。", confidence: 0.82)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 200,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "api",
            lockedPrefix: nil,
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let task = Task {
            await runtime.recommendation(for: request)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()

        let state = await task.value
        let requests = await provider.requests

        XCTAssertEqual(state, .idle)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .debounceStart && $0.reason == "waiting_for_idle"
        })
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .cancelled && $0.reason == "debounce_cancelled_by_new_input"
        })
    }

    func testProviderCancellationErrorDoesNotEnterCooldownOrUnavailable() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = FailingLLMProvider(error: CancellationError())
        let runtime = AIRecommendationRuntime(
            provider: provider,
            healthMonitor: AIHealthMonitor(failureThreshold: 1, cooldownSeconds: 60),
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = cancellableRecommendationRequest()

        let first = await runtime.recommendation(for: request)
        let second = await runtime.recommendation(for: request)
        let requestCount = await provider.requestCount

        XCTAssertEqual(first, .idle)
        XCTAssertEqual(second, .idle)
        XCTAssertEqual(requestCount, 2)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .cancelled && $0.reason == "task_cancelled"
        })
        XCTAssertFalse(diagnosticSink.events.contains { $0.stage == .providerError })
        XCTAssertFalse(diagnosticSink.events.contains { $0.stage == .cooldownActive })
    }

    func testProviderURLErrorCancelledDoesNotEnterCooldownOrUnavailable() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = FailingLLMProvider(error: URLError(.cancelled))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            healthMonitor: AIHealthMonitor(failureThreshold: 1, cooldownSeconds: 60),
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = cancellableRecommendationRequest()

        let first = await runtime.recommendation(for: request)
        let second = await runtime.recommendation(for: request)
        let requestCount = await provider.requestCount

        XCTAssertEqual(first, .idle)
        XCTAssertEqual(second, .idle)
        XCTAssertEqual(requestCount, 2)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .cancelled && $0.reason == "transport_cancelled"
        })
        XCTAssertFalse(diagnosticSink.events.contains { $0.stage == .providerError })
        XCTAssertFalse(diagnosticSink.events.contains { $0.stage == .cooldownActive })
    }

    func testRecommendationDiagnosticsRecordStructuredSchemaFallback() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(
            candidates: [LLMCandidate(text: "继续推进", confidence: 0.88)],
            diagnostics: ["structured_schema_unsupported"]
        ))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        _ = await runtime.recommendation(for: request)

        XCTAssertTrue(diagnosticSink.events.contains { $0.stage == .structuredSchemaRequest })
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .structuredSchemaUnsupported && $0.reason == "structured_schema_unsupported"
        })
    }

    func testRecommendationDiagnosticsRecordStructuredDecodeErrors() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = FailingLLMProvider(error: ProviderError.invalidResponse("structured_decode_error: missing candidates"))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)

        XCTAssertEqual(state, .unavailable(reason: "AI 暂不可用"))
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .structuredDecodeError
                && $0.reason == "structured_decode_error: missing candidates"
        })
    }

    func testRecommendationDiagnosticsRecordSanitizerRejectReason() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "你好", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            appBundleID: "com.apple.TextEdit",
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)

        XCTAssertEqual(state, .ineligible(reason: "AI 无推荐"))
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .sanitizeReject && $0.reason == "sanitize_reject_same_as_prefix"
        })
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .sanitizeEmpty && $0.reason == "same_as_prefix"
        })
    }

    func testRecommendationReadsContextDocumentsAndCachesResult() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let correctionURL = directory.appendingPathComponent("CORRECTION.md")
        try """
        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - Prefer concise Chinese.
        <!-- KNOWTYPE:END GENERATED -->

        ## User Notes
        """.write(to: environmentURL, atomically: true, encoding: .utf8)
        try """
        # KnowType Correction Instructions

        - Preserve API tokens.
        """.write(to: correctionURL, atomically: true, encoding: .utf8)

        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            correctionStore: CorrectionInstructionStore(fileURL: correctionURL),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            appBundleID: "com.apple.TextEdit",
            locale: .zhCN,
            compositionID: 1
        )

        let first = await runtime.recommendation(for: request)
        let second = await runtime.recommendation(for: request)
        let requests = await provider.requests

        guard case .ready(let firstCandidate) = first,
              case .ready(let secondCandidate) = second else {
            return XCTFail("expected ready AI recommendations")
        }
        XCTAssertEqual(firstCandidate.displayText, "你好继续推进")
        XCTAssertEqual(secondCandidate.displayText, "你好继续推进")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].task, .continuation)
        XCTAssertEqual(requests[0].lockedPrefix, "你好")
        XCTAssertEqual(requests[0].contextDocuments["ENV.md"]?.contains("Prefer concise Chinese"), true)
        XCTAssertEqual(requests[0].contextDocuments["CORRECTION.md"]?.contains("Preserve API tokens"), true)
    }

    func testRecommendationCacheIncludesRawInput() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let candidate = CorrectionCandidate(
            text: "你好",
            source: "traditional",
            confidence: 1,
            correctionLevel: .contextual
        )

        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "nihao",
                traditionalCandidate: candidate,
                compositionID: 1
            )
        )
        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "ni hao",
                traditionalCandidate: candidate,
                compositionID: 2
            )
        )
        let requests = await provider.requests

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.rawInput), ["nihao", "ni hao"])
    }

    func testRecommendationIncludesLexicalProfileAndCacheKey() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let candidate = CorrectionCandidate(
            text: "你好",
            source: "traditional",
            confidence: 1,
            correctionLevel: .contextual
        )
        let builder = LexicalContextBuilder()
        let firstLexical = try! XCTUnwrap(builder.snapshot(rimeCandidates: ["你好"], recentCommits: ["请同步这个方案"]))
        let secondLexical = try! XCTUnwrap(builder.snapshot(rimeCandidates: ["你好"], recentCommits: ["这个方向可以继续"]))

        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "nihao",
                traditionalCandidate: candidate,
                compositionID: 1,
                lexicalContext: firstLexical
            )
        )
        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "nihao",
                traditionalCandidate: candidate,
                compositionID: 1,
                lexicalContext: firstLexical
            )
        )
        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "nihao",
                traditionalCandidate: candidate,
                compositionID: 1,
                lexicalContext: secondLexical
            )
        )
        let requests = await provider.requests

        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].contextDocuments["LEXICAL_PROFILE.md"]?.contains("请同步这个方案") == true)
        XCTAssertTrue(requests[1].contextDocuments["LEXICAL_PROFILE.md"]?.contains("这个方向可以继续") == true)
        XCTAssertNotEqual(firstLexical.sha256, secondLexical.sha256)
    }

    func testRecommendationIncludesFeedbackContextAndCacheKey() async {
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.88)
        ]))
        let runtime = AIRecommendationRuntime(provider: provider, debounceMilliseconds: 0)
        let candidate = CorrectionCandidate(
            text: "你好",
            source: "traditional",
            confidence: 1,
            correctionLevel: .contextual
        )
        let firstFeedback = AIAcceptedFeedbackContextSnapshot(
            summary: AIAcceptedFeedbackSummary(
                historyHash: "feedback-a",
                feedbackCount: 1,
                strongCount: 1,
                avoidTerms: ["冗长表达"],
                styleAdjustments: ["Prefer shorter AI continuations when context is ambiguous."],
                replacementPatterns: [],
                sourceSummary: ["accepted-ai-feedback-summary: records=1 strong=1 history=feedback"]
            )
        )
        let secondFeedback = AIAcceptedFeedbackContextSnapshot(
            summary: AIAcceptedFeedbackSummary(
                historyHash: "feedback-b",
                feedbackCount: 1,
                strongCount: 1,
                avoidTerms: ["机械复述"],
                styleAdjustments: ["Avoid confidently completing with phrases the user tends to delete soon after accepting."],
                replacementPatterns: [],
                sourceSummary: ["accepted-ai-feedback-summary: records=1 strong=1 history=feedback"]
            )
        )

        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "nihao",
                traditionalCandidate: candidate,
                compositionID: 1,
                feedbackContext: firstFeedback
            )
        )
        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "nihao",
                traditionalCandidate: candidate,
                compositionID: 1,
                feedbackContext: firstFeedback
            )
        )
        _ = await runtime.recommendation(
            for: AIRecommendationRequest(
                rawInput: "nihao",
                traditionalCandidate: candidate,
                compositionID: 1,
                feedbackContext: secondFeedback
            )
        )

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].contextDocuments["AI_FEEDBACK.md"]?.contains("冗长表达") == true)
        XCTAssertTrue(requests[1].contextDocuments["AI_FEEDBACK.md"]?.contains("机械复述") == true)
        XCTAssertNotEqual(firstFeedback.sha256, secondFeedback.sha256)
    }

    func testLexicalProfileFiltersStandaloneProtectedTechnicalTokens() throws {
        let snapshot = try XCTUnwrap(
            LexicalContextBuilder().snapshot(
                rimeCandidates: ["当前候选", "API", "JSON"],
                recentCommits: ["请同步这个方案"],
                selectionHistory: ["snake_case"]
            )
        )

        XCTAssertTrue(snapshot.markdown.contains("请同步这个方案"))
        XCTAssertFalse(snapshot.terms.contains { $0.text == "当前候选" })
        XCTAssertFalse(snapshot.terms.contains { $0.text == "API" })
        XCTAssertFalse(snapshot.terms.contains { $0.text == "JSON" })
        XCTAssertFalse(snapshot.terms.contains { $0.text == "snake_case" })
    }

    func testSecretLikeInputDoesNotCallProvider() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = RecordingLLMProvider(response: LLMResponse(candidates: [
            LLMCandidate(text: " should not be used")
        ]))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "API_KEY=sk-abcdefghijklmnopqrstuvwxyz",
            traditionalCandidate: CorrectionCandidate(
                text: "API_KEY=sk-abcdefghijklmnopqrstuvwxyz",
                source: "raw",
                confidence: 1,
                correctionLevel: .none
            ),
            compositionID: 1
        )

        let state = await runtime.recommendation(for: request)
        let requests = await provider.requests

        XCTAssertEqual(state, .ineligible(reason: "AI 已禁用"))
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(diagnosticSink.events.contains {
            $0.stage == .skippedProtectedText && $0.reason == "secret_like_text"
        })
    }

    func testRepeatedProviderFailuresEnterCooldown() async {
        let provider = FailingLLMProvider(error: ProviderError.httpStatus(503, "unavailable"))
        let runtime = AIRecommendationRuntime(
            provider: provider,
            healthMonitor: AIHealthMonitor(failureThreshold: 1, cooldownSeconds: 60),
            debounceMilliseconds: 0
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            compositionID: 1
        )

        let first = await runtime.recommendation(for: request)
        let second = await runtime.recommendation(for: request)
        let requestCount = await provider.requestCount

        XCTAssertEqual(first, .unavailable(reason: "AI 暂不可用"))
        XCTAssertEqual(second, .unavailable(reason: "AI 暂不可用"))
        XCTAssertEqual(requestCount, 1)
    }

    func testEmptyRecommendationDoesNotEnterCooldown() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = QueuedLLMProvider(responses: [
            LLMResponse(candidates: []),
            LLMResponse(candidates: [
                LLMCandidate(text: "继续推进", confidence: 0.9)
            ])
        ])
        let runtime = AIRecommendationRuntime(
            provider: provider,
            healthMonitor: AIHealthMonitor(failureThreshold: 1, cooldownSeconds: 60),
            debounceMilliseconds: 0,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            compositionID: 1
        )

        let first = await runtime.recommendation(for: request)
        let second = await runtime.recommendation(for: request)
        let requestCount = await provider.requestCount

        XCTAssertEqual(first, .ineligible(reason: "AI 无推荐"))
        guard case .ready(let candidate) = second else {
            return XCTFail("expected second recommendation to bypass cooldown")
        }
        XCTAssertEqual(candidate.displayText, "你好继续推进")
        XCTAssertEqual(requestCount, 2)
        let sanitizeEmptyEvents = diagnosticSink.events.filter { $0.stage == .sanitizeEmpty }
        XCTAssertEqual(sanitizeEmptyEvents.count, 1)
        XCTAssertEqual(sanitizeEmptyEvents.first?.candidateCount, 0)
        XCTAssertEqual(sanitizeEmptyEvents.first?.acceptedCount, 0)
    }

    func testHardTimeoutReturnsWithoutWaitingForCancellationResistantProvider() async {
        let diagnosticSink = RecordingDiagnosticSink()
        let provider = SlowCancellationResistantLLMProvider()
        let runtime = AIRecommendationRuntime(
            provider: provider,
            debounceMilliseconds: 0,
            hardTimeoutMilliseconds: 20,
            diagnosticSink: diagnosticSink
        )
        let request = AIRecommendationRequest(
            rawInput: "nihao",
            traditionalCandidate: CorrectionCandidate(
                text: "你好",
                source: "traditional",
                confidence: 1,
                correctionLevel: .contextual
            ),
            compositionID: 1
        )
        let start = Date()

        let state = await runtime.recommendation(for: request)
        let requestCount = await provider.requestCount

        XCTAssertEqual(state, .unavailable(reason: "AI 请求超时"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(requestCount, 1)
        let timeoutEvent = diagnosticSink.events.first { $0.stage == .timeout }
        XCTAssertEqual(timeoutEvent?.reason, "hard_timeout")
        XCTAssertNotNil(timeoutEvent?.elapsedMilliseconds)
    }

    func testDocumentStoresCreateDefaultsAndPreserveUserNotes() throws {
        let directory = temporaryDirectory()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md")
        )
        let correctionStore = CorrectionInstructionStore(
            fileURL: directory.appendingPathComponent("CORRECTION.md")
        )

        let environment = try environmentStore.loadSnapshot()
        let correction = try correctionStore.loadSnapshot()

        XCTAssertTrue(environment.content.contains("## User Notes"))
        XCTAssertTrue(correction.content.contains("临近键"))

        let updated = try environmentStore.replaceGeneratedSection(with: "## Global Style\n- Test style.")
        XCTAssertTrue(updated.content.contains("## Global Style\n- Test style."))
        XCTAssertTrue(updated.content.contains("## User Notes"))
    }

    func testEnvironmentReplacementPreservesExistingContentWhenMarkersAreMissing() {
        let current = """
        # KnowType Environment

        ## User Notes
        - Keep this manual note.
        """

        let updated = EnvironmentDocumentStore.replacingGeneratedSection(
            in: current,
            with: "## Global Style\n- Learned style."
        )

        XCTAssertTrue(updated.contains("## Global Style\n- Learned style."))
        XCTAssertTrue(updated.contains("## User Notes"))
        XCTAssertTrue(updated.contains("- Keep this manual note."))
    }

    func testEnvironmentReplacementRepairsDuplicateGeneratedMarkers() {
        let current = """
        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - Old generated section.
        <!-- KNOWTYPE:END GENERATED -->

        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - Duplicate generated section.
        <!-- KNOWTYPE:END GENERATED -->

        ## User Notes
        - Keep this manual note.
        """

        let updated = EnvironmentDocumentStore.replacingGeneratedSection(
            in: current,
            with: "## Global Style\n- Learned style."
        )

        XCTAssertEqual(updated.components(separatedBy: EnvironmentDocumentStore.generatedStart).count - 1, 1)
        XCTAssertEqual(updated.components(separatedBy: EnvironmentDocumentStore.generatedEnd).count - 1, 1)
        XCTAssertTrue(updated.contains("## Global Style\n- Learned style."))
        XCTAssertFalse(updated.contains("Duplicate generated section"))
        XCTAssertTrue(updated.contains("## User Notes"))
        XCTAssertTrue(updated.contains("- Keep this manual note."))
    }

    func testEnvironmentRepairPreservesUnmatchedDuplicateBeginAndStandaloneEnd() {
        let current = """
        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - Old generated section.
        <!-- KNOWTYPE:END GENERATED -->

        ## User Notes
        - The next line is literal documentation.
        <!-- KNOWTYPE:END GENERATED -->
        <!-- KNOWTYPE:BEGIN GENERATED -->
        - A literal paired marker block in notes must be preserved.
        <!-- KNOWTYPE:END GENERATED -->
        <!-- KNOWTYPE:BEGIN GENERATED -->
        - Keep this unmatched marker and everything after it.
        - Keep this manual note.
        """

        let repaired = EnvironmentDocumentStore.repairingGeneratedSectionMarkers(in: current)

        XCTAssertTrue(repaired.contains("- The next line is literal documentation."))
        XCTAssertTrue(repaired.contains("<!-- KNOWTYPE:END GENERATED -->"))
        XCTAssertTrue(repaired.contains("- A literal paired marker block in notes must be preserved."))
        XCTAssertTrue(repaired.contains("- Keep this unmatched marker and everything after it."))
        XCTAssertTrue(repaired.contains("- Keep this manual note."))
    }

    func testEnvironmentLoadRepairsDuplicateGeneratedMarkersAndPersistsRepair() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let polluted = """
        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - Keep generated.
        <!-- KNOWTYPE:END GENERATED -->

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - Remove duplicate.
        <!-- KNOWTYPE:END GENERATED -->

        ## User Notes
        - Keep user note.
        """
        try Data(polluted.utf8).write(to: environmentURL, options: .atomic)

        let store = EnvironmentDocumentStore(fileURL: environmentURL)
        let snapshot = try store.loadSnapshot()
        let diskContent = try String(contentsOf: environmentURL, encoding: .utf8)

        XCTAssertNotEqual(diskContent, polluted)
        XCTAssertEqual(snapshot.content, diskContent)
        XCTAssertEqual(snapshot.content.components(separatedBy: EnvironmentDocumentStore.generatedStart).count - 1, 1)
        XCTAssertEqual(snapshot.content.components(separatedBy: EnvironmentDocumentStore.generatedEnd).count - 1, 1)
        XCTAssertFalse(snapshot.content.contains("Remove duplicate"))
        XCTAssertTrue(snapshot.content.contains("- Keep user note."))
    }

    func testEnvironmentLoadReturnsRepairedSnapshotWhenRepairWriteFails() throws {
        let fileManager = FileManager.default
        let directory = temporaryDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? fileManager.removeItem(at: directory)
        }
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let polluted = """
        # KnowType Environment

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - Keep generated.
        <!-- KNOWTYPE:END GENERATED -->

        <!-- KNOWTYPE:BEGIN GENERATED -->
        ## Global Style
        - Remove duplicate.
        <!-- KNOWTYPE:END GENERATED -->

        ## User Notes
        - Keep user note.
        """
        try Data(polluted.utf8).write(to: environmentURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        let store = EnvironmentDocumentStore(fileURL: environmentURL)
        let snapshot = try store.loadSnapshot()
        let diskContent = try String(contentsOf: environmentURL, encoding: .utf8)

        XCTAssertEqual(diskContent, polluted)
        XCTAssertEqual(snapshot.content.components(separatedBy: EnvironmentDocumentStore.generatedStart).count - 1, 1)
        XCTAssertEqual(snapshot.content.components(separatedBy: EnvironmentDocumentStore.generatedEnd).count - 1, 1)
        XCTAssertFalse(snapshot.content.contains("Remove duplicate"))
        XCTAssertTrue(snapshot.content.contains("- Keep user note."))
    }
}

private actor RecordingLLMProvider: LLMProvider {
    nonisolated let providerName = "recording"
    private let response: LLMResponse
    private var recordedRequests: [LLMRequest] = []

    init(response: LLMResponse) {
        self.response = response
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        return response
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

private final class SequencedProviderLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var providers: [(any LLMProvider)?]
    private var loadCount = 0

    init(_ providers: [(any LLMProvider)?]) {
        self.providers = providers
    }

    func load() -> (any LLMProvider)? {
        lock.lock()
        defer { lock.unlock() }
        loadCount += 1
        guard !providers.isEmpty else {
            return nil
        }
        return providers.removeFirst()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCount
    }
}

private actor FailingLLMProvider: LLMProvider {
    nonisolated let providerName = "failing"
    private let error: Error
    private var count = 0

    init(error: Error) {
        self.error = error
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        count += 1
        throw error
    }

    var requestCount: Int {
        count
    }
}

private actor QueuedLLMProvider: LLMProvider {
    nonisolated let providerName = "queued"
    private var responses: [LLMResponse]
    private var count = 0

    init(responses: [LLMResponse]) {
        self.responses = responses
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        count += 1
        guard !responses.isEmpty else {
            return LLMResponse(candidates: [])
        }
        return responses.removeFirst()
    }

    var requestCount: Int {
        count
    }
}

private actor SlowCancellationResistantLLMProvider: LLMProvider {
    nonisolated let providerName = "slow"
    private var count = 0

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        count += 1
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: 20_000_000)
            } catch {
                continue
            }
        }
        return LLMResponse(candidates: [
            LLMCandidate(text: "继续推进", confidence: 0.9)
        ])
    }

    var requestCount: Int {
        count
    }
}

private final class RecordingDiagnosticSink: AIRecommendationDiagnosticSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [AIRecommendationDiagnosticEvent] = []

    func record(_ event: AIRecommendationDiagnosticEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }

    var events: [AIRecommendationDiagnosticEvent] {
        lock.lock()
        let events = recordedEvents
        lock.unlock()
        return events
    }
}

private func cancellableRecommendationRequest() -> AIRecommendationRequest {
    AIRecommendationRequest(
        rawInput: "nihao",
        traditionalCandidate: CorrectionCandidate(
            text: "你好",
            source: "traditional",
            confidence: 1,
            correctionLevel: .contextual
        ),
        appBundleID: "com.apple.TextEdit",
        compositionID: 1
    )
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeAITests-\(UUID().uuidString)", isDirectory: true)
}
