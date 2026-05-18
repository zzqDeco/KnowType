import Foundation
import XCTest
@testable import KnowTypeAI
import KnowTypeCore

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

private func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeAIContextTests-\(UUID().uuidString)", isDirectory: true)
}
