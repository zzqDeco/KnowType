import Foundation
import XCTest
@testable import KnowTypeAI
import KnowTypeCore
import KnowTypeProviders

final class AIContextMemoryRuntimeTests: XCTestCase {
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

private func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeAIContextTests-\(UUID().uuidString)", isDirectory: true)
}
