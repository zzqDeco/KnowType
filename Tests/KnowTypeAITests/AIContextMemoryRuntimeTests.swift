import Foundation
import XCTest
@testable import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

final class AIContextMemoryRuntimeTests: XCTestCase {
    func testLazyDefaultContextMemorySkipsMissingProviderWithoutCreatingEvents() async {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events", isDirectory: true)
        let factory = ContextRuntimeFactoryProbe(
            eventsDirectory: eventsDirectory,
            environmentURL: directory.appendingPathComponent("ENV.md")
        )
        let runtime = LazyDefaultAIContextMemoryRuntime(
            providerLoader: { nil },
            runtimeFactory: { factory.make(provider: $0) }
        )

        await runtime.record(
            AITypingEvent(
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit",
                rawInput: "nihao",
                committedText: "你好",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )

        XCTAssertFalse(factory.wasCalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventsDirectory.path))
    }

    func testRegistryContextMemorySkipsEventUntilProviderIsUsable() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events", isDirectory: true)
        )
        let providerB = NamedLLMProvider(
            name: "provider-b",
            responseText: "## Global Style\n- Provider B digest."
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "0", count: 64),
            provider: nil
        )
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source),
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(makeContextEvent(rawInput: "before-provider", committedText: "早期"))
        let pendingWithoutProvider = try await eventStore.pendingEvents()
        XCTAssertTrue(pendingWithoutProvider.isEmpty)

        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        await runtime.record(makeContextEvent(rawInput: "after-provider", committedText: "后来"))

        let requests = await providerB.recordedRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(requests[0].rawInput?.contains("before-provider") == true)
        XCTAssertTrue(requests[0].rawInput?.contains("after-provider") == true)
    }

    func testRecordProcessesBatchAndUpdatesEnvironmentGeneratedSection() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events", isDirectory: true)
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let provider = DigestLLMProvider(generatedMarkdown: """
        ## Global Style
        - The user often writes concise product notes.

        ## App Habits
        - TextEdit: drafts short Chinese phrases.

        ## Recent Work Context
        - Testing KnowType input behavior.
        """)
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(
            AITypingEvent(
                appBundleID: "com.apple.TextEdit",
                appName: "TextEdit",
                rawInput: "nihao",
                committedText: "你好",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )

        let environment = try String(contentsOf: environmentURL, encoding: .utf8)
        let pendingEvents = try await eventStore.pendingEvents()
        let requests = await provider.requests

        XCTAssertTrue(environment.contains("The user often writes concise product notes."))
        XCTAssertTrue(environment.contains("## User Notes"))
        XCTAssertTrue(pendingEvents.isEmpty)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].task, .contextDigest)
        XCTAssertEqual(requests[0].contextDocuments["ENV.md"]?.contains("KnowType Environment"), true)
    }

    func testLevelZeroEventIsSanitizedBeforeItIsLogged() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events"))
        let runtime = AIContextMemoryRuntime(
            provider: nil,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(
            AITypingEvent(
                appBundleID: nil,
                appName: nil,
                rawInput: "https://example.com/api",
                committedText: "https://example.com/api",
                commitKind: .raw,
                candidateSource: "raw"
            )
        )

        let pendingEvents = try await eventStore.pendingEvents()

        XCTAssertEqual(pendingEvents.count, 1)
        XCTAssertEqual(pendingEvents[0].rawInput, "protected:url")
        XCTAssertEqual(pendingEvents[0].committedText, "protected:url")
        XCTAssertEqual(pendingEvents[0].candidateSource, "protected")
    }

    func testConcurrentStoresAppendWithoutDroppingEvents() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events", isDirectory: true)
        let firstStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let secondStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let store = index.isMultiple(of: 2) ? firstStore : secondStore
                    try await store.append(
                        AITypingEvent(
                            rawInput: "raw-\(index)",
                            committedText: "text-\(index)",
                            commitKind: .traditional,
                            candidateSource: "traditional"
                        )
                    )
                }
            }
            try await group.waitForAll()
        }

        let events = try await firstStore.pendingEvents()
        let committedTexts = Set(events.compactMap(\.committedText))

        XCTAssertEqual(events.count, 40)
        XCTAssertEqual(committedTexts.count, 40)
        XCTAssertTrue(committedTexts.contains("text-0"))
        XCTAssertTrue(committedTexts.contains("text-39"))
    }

    func testRecordBelowBatchDoesNotDigestImmediately() async throws {
        let directory = makeTemporaryDirectory()
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Should not run yet.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events")),
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 2,
            minimumInterval: 600
        )

        await runtime.record(
            AITypingEvent(
                rawInput: "nihao",
                committedText: "你好",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testDigestArchivesOnlyEventsIncludedInProviderRequest() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events", isDirectory: true)
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let provider = SuspendedDigestLLMProvider()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        let firstRecord = Task {
            await runtime.record(
                AITypingEvent(
                    rawInput: "nihao",
                    committedText: "你好",
                    commitKind: .traditional,
                    candidateSource: "traditional"
                )
            )
        }
        try await waitUntilProviderReceivesRequest(provider)

        await runtime.record(
            AITypingEvent(
                rawInput: "zaijian",
                committedText: "再见",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )
        await provider.finish(generatedMarkdown: "## Global Style\n- Finished digest.")
        await firstRecord.value

        let pendingEvents = try await eventStore.pendingEvents()
        let requests = await provider.requests

        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].rawInput?.contains("nihao") == true)
        XCTAssertFalse(requests[0].rawInput?.contains("zaijian") == true)
        XCTAssertEqual(pendingEvents.map(\.rawInput), ["zaijian"])
    }

    func testProtectedOnlyBatchIsArchivedWithoutProviderDigest() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events", isDirectory: true)
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Should not be used.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(
            AITypingEvent(
                rawInput: "https://example.com/api",
                committedText: "https://example.com/api",
                commitKind: .raw,
                candidateSource: "raw"
            )
        )

        let requests = await provider.requests
        let pendingEvents = try await eventStore.pendingEvents()

        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(pendingEvents.isEmpty)
    }

    func testProtectedExternalDeleteIsArchivedWithoutProviderDigest() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events", isDirectory: true)
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Should not be used.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(
            AITypingEvent(
                appBundleID: "com.apple.Terminal",
                appName: "Terminal",
                rawInput: nil,
                committedText: nil,
                commitKind: .externalDelete,
                candidateSource: "external-delete",
                deleteCountBeforeCommit: 1
            )
        )

        let requests = await provider.requests
        let pendingEvents = try await eventStore.pendingEvents()

        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(pendingEvents.isEmpty)
    }

    func testDigestFailureIsThrottledUntilMinimumInterval() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events", isDirectory: true)
        )
        let provider = FailingDigestLLMProvider()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(
            AITypingEvent(
                rawInput: "nihao",
                committedText: "你好",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )
        await runtime.record(
            AITypingEvent(
                rawInput: "zaijian",
                committedText: "再见",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )

        let requests = await provider.requestCount
        let pendingEvents = try await eventStore.pendingEvents()

        XCTAssertEqual(requests, 1)
        XCTAssertEqual(pendingEvents.map(\.rawInput), ["nihao", "zaijian"])
    }

    func testEmptyDigestResponseIsThrottledUntilMinimumInterval() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events", isDirectory: true)
        )
        let provider = DigestLLMProvider(generatedMarkdown: "   ")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(
            AITypingEvent(
                rawInput: "nihao",
                committedText: "你好",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )
        await runtime.record(
            AITypingEvent(
                rawInput: "zaijian",
                committedText: "再见",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )

        let requests = await provider.requests
        let pendingEvents = try await eventStore.pendingEvents()

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(pendingEvents.map(\.rawInput), ["nihao", "zaijian"])
    }

    func testMultipartDigestResponsePreservesAllGeneratedLines() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events", isDirectory: true)
        )
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let provider = MultipartDigestLLMProvider(parts: [
            "## Global Style",
            "- Uses concise text.",
            "## App Habits",
            "- TextEdit: writes short notes."
        ])
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(
            AITypingEvent(
                rawInput: "nihao",
                committedText: "你好",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )

        let environment = try String(contentsOf: environmentURL, encoding: .utf8)

        XCTAssertTrue(environment.contains("## Global Style"))
        XCTAssertTrue(environment.contains("- Uses concise text."))
        XCTAssertTrue(environment.contains("## App Habits"))
        XCTAssertTrue(environment.contains("- TextEdit: writes short notes."))
    }

    func testTwoControllerReferencesIssueOneDigestForOnePendingSnapshot() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events", isDirectory: true)
        )
        let provider = DelayedDigestLLMProvider(
            generatedMarkdown: "## Global Style\n- Concurrent digest.",
            delayNanoseconds: 80_000_000
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )
        let firstControllerRuntime = runtime
        let secondControllerRuntime = runtime

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await firstControllerRuntime.record(
                    AITypingEvent(
                        rawInput: "nihao",
                        committedText: "你好",
                        commitKind: .traditional,
                        candidateSource: "traditional"
                    )
                )
            }
            group.addTask {
                await secondControllerRuntime.record(
                    AITypingEvent(
                        rawInput: "zaijian",
                        committedText: "再见",
                        commitKind: .traditional,
                        candidateSource: "traditional"
                    )
                )
            }
        }

        let requests = await provider.requests

        XCTAssertEqual(requests.count, 1)
    }

    func testContextDigestReloadsAtoBWithoutRestart() async throws {
        let directory = makeTemporaryDirectory()
        let providerA = NamedLLMProvider(
            name: "provider-a",
            responseText: "## Global Style\n- Provider A digest."
        )
        let providerB = NamedLLMProvider(
            name: "provider-b",
            responseText: "## Global Style\n- Provider B digest."
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let signal = TestProviderRevisionSignal()
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source, signal: signal),
            eventStore: TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events")),
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(makeContextEvent(rawInput: "nihao", committedText: "你好"))
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        signal.send(2)
        await runtime.record(makeContextEvent(rawInput: "zaijian", committedText: "再见"))

        let environment = try String(
            contentsOf: directory.appendingPathComponent("ENV.md"),
            encoding: .utf8
        )
        let providerACount = await providerA.requestCount
        let providerBCount = await providerB.requestCount
        XCTAssertEqual(providerACount, 1)
        XCTAssertEqual(providerBCount, 1)
        XCTAssertTrue(environment.contains("Provider B digest"))
        XCTAssertFalse(environment.contains("Provider A digest"))
    }

    func testContextGenerationChangeCancelsOldDigestAndPreservesPendingEvents() async throws {
        let directory = makeTemporaryDirectory()
        let eventsURL = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsURL)
        let providerA = SuspendedGenerationLLMProvider(name: "provider-a")
        let providerB = NamedLLMProvider(
            name: "provider-b",
            responseText: "## Global Style\n- Provider B digest."
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let signal = TestProviderRevisionSignal()
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source, signal: signal),
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600
        )

        let oldDigest = Task {
            await runtime.record(makeContextEvent(rawInput: "nihao", committedText: "你好"))
        }
        try await waitUntil { await providerA.requestCount == 1 }
        await runtime.record(makeContextEvent(rawInput: "zaijian", committedText: "再见"))
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        signal.send(2)
        try await waitUntil { await providerA.cancellationCount == 1 }
        await providerA.finish(responseText: "## Global Style\n- Provider A stale digest.")
        await oldDigest.value

        let pendingBeforeRetry = try await eventStore.pendingEvents()
        let staleEnvironment = try String(contentsOf: environmentURL, encoding: .utf8)
        XCTAssertEqual(pendingBeforeRetry.map(\.rawInput), ["nihao", "zaijian"])
        XCTAssertFalse(staleEnvironment.contains("Provider A stale digest"))

        await runtime.processIfNeeded()

        let pendingAfterRetry = try await eventStore.pendingEvents()
        let currentEnvironment = try String(contentsOf: environmentURL, encoding: .utf8)
        let providerBRequests = await providerB.recordedRequests
        XCTAssertTrue(pendingAfterRetry.isEmpty)
        XCTAssertTrue(currentEnvironment.contains("Provider B digest"))
        XCTAssertEqual(providerBRequests.count, 1)
        XCTAssertTrue(providerBRequests[0].rawInput?.contains("nihao") == true)
        XCTAssertTrue(providerBRequests[0].rawInput?.contains("zaijian") == true)
    }

    func testProtectedOnlyPendingRegistryBatchDoesNotReadProviderFiles() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events"))
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: NamedLLMProvider(name: "provider-a", responseText: "unused")
        )
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source),
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        try await eventStore.append(
            AITypingEvent(
                rawInput: "protected:redacted",
                committedText: "protected:redacted",
                commitKind: .raw,
                candidateSource: "protected"
            )
        )
        await runtime.processIfNeeded()
        let pendingEvents = try await eventStore.pendingEvents()

        XCTAssertTrue(pendingEvents.isEmpty)
        XCTAssertEqual(source.revisionReadCount, 0)
        XCTAssertEqual(source.runtimeLoadCount, 0)
    }

    func testRegistryDigestFailureChecksRevisionBeforeRespectingMinimumInterval() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events"))
        let provider = FailingDigestLLMProvider()
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: provider
        )
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source),
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(makeContextEvent(rawInput: "nihao", committedText: "你好"))
        await runtime.processIfNeeded()

        let requestCount = await provider.requestCount
        let pendingEvents = try await eventStore.pendingEvents()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(source.revisionReadCount, 3)
        XCTAssertEqual(source.runtimeLoadCount, 1)
        XCTAssertEqual(pendingEvents.count, 1)
    }

    func testMissedNotificationGenerationChangeBypassesDigestFailureCooldown() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events"))
        let providerA = FailingDigestLLMProvider()
        let providerB = NamedLLMProvider(
            name: "provider-b",
            responseText: "## Global Style\n- Provider B recovered."
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source),
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600
        )

        await runtime.record(makeContextEvent(rawInput: "nihao", committedText: "你好"))
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        await runtime.record(makeContextEvent(rawInput: "zaijian", committedText: "再见"))

        let providerARequestCount = await providerA.requestCount
        XCTAssertEqual(providerARequestCount, 1)
        let providerBRequests = await providerB.recordedRequests
        XCTAssertEqual(providerBRequests.count, 1)
        XCTAssertTrue(providerBRequests[0].rawInput?.contains("nihao") == true)
        XCTAssertTrue(providerBRequests[0].rawInput?.contains("zaijian") == true)
        let pendingEvents = try await eventStore.pendingEvents()
        XCTAssertTrue(pendingEvents.isEmpty)
    }
}

private func makeContextEvent(rawInput: String, committedText: String) -> AITypingEvent {
    AITypingEvent(
        rawInput: rawInput,
        committedText: committedText,
        commitKind: .traditional,
        candidateSource: "traditional"
    )
}

private actor DigestLLMProvider: LLMProvider {
    nonisolated let providerName = "digest"
    private let generatedMarkdown: String
    private var recordedRequests: [LLMRequest] = []

    init(generatedMarkdown: String) {
        self.generatedMarkdown = generatedMarkdown
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        return LLMResponse(candidates: [
            LLMCandidate(text: generatedMarkdown, confidence: 0.9)
        ])
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

private actor SuspendedDigestLLMProvider: LLMProvider {
    nonisolated let providerName = "suspended-digest"
    private var recordedRequests: [LLMRequest] = []
    private var continuation: CheckedContinuation<LLMResponse, Error>?

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(generatedMarkdown: String) {
        continuation?.resume(
            returning: LLMResponse(candidates: [
                LLMCandidate(text: generatedMarkdown, confidence: 0.9)
            ])
        )
        continuation = nil
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

private actor FailingDigestLLMProvider: LLMProvider {
    nonisolated let providerName = "failing-digest"
    private var count = 0

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        count += 1
        throw ProviderError.httpStatus(503, "unavailable")
    }

    var requestCount: Int {
        count
    }
}

private actor MultipartDigestLLMProvider: LLMProvider {
    nonisolated let providerName = "multipart-digest"
    private let parts: [String]

    init(parts: [String]) {
        self.parts = parts
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(candidates: parts.map { LLMCandidate(text: $0, confidence: 0.9) })
    }
}

private actor DelayedDigestLLMProvider: LLMProvider {
    nonisolated let providerName = "delayed-digest"
    private let generatedMarkdown: String
    private let delayNanoseconds: UInt64
    private var recordedRequests: [LLMRequest] = []

    init(generatedMarkdown: String, delayNanoseconds: UInt64) {
        self.generatedMarkdown = generatedMarkdown
        self.delayNanoseconds = delayNanoseconds
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return LLMResponse(candidates: [
            LLMCandidate(text: generatedMarkdown, confidence: 0.9)
        ])
    }

    var requests: [LLMRequest] {
        recordedRequests
    }
}

private func waitUntilProviderReceivesRequest(
    _ provider: SuspendedDigestLLMProvider,
    timeout: TimeInterval = 2
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await !provider.requests.isEmpty {
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("provider did not receive a digest request")
}

private final class ContextRuntimeFactoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let eventsDirectory: URL
    private let environmentURL: URL
    private var called = false

    init(eventsDirectory: URL, environmentURL: URL) {
        self.eventsDirectory = eventsDirectory
        self.environmentURL = environmentURL
    }

    func make(provider: any LLMProvider) -> AIContextMemoryRuntime {
        lock.lock()
        called = true
        lock.unlock()
        return AIContextMemoryRuntime(
            provider: provider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600
        )
    }

    var wasCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return called
    }
}

private func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeAIContextTests-\(UUID().uuidString)", isDirectory: true)
}
