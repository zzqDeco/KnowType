import CryptoKit
import Darwin
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
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
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
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
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
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
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

    func testInitialPendingBelowBatchDrainsAtForcedDeadline() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let provider = DelayedDigestLLMProvider(
            generatedMarkdown: "## Global Style\n- forced deadline",
            delayNanoseconds: 20_000_000
        )
        let eventStore = TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events"))
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 2,
            minimumInterval: 1,
            maximumPendingAge: 1,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.record(makeContextEvent(rawInput: "first", committedText: "第一"))
        let requestsBeforeDeadline = await provider.requests
        XCTAssertTrue(requestsBeforeDeadline.isEmpty)
        clock.advance(by: 2)

        try await waitUntil { !(await provider.requests).isEmpty }
        try await waitUntil {
            let pending = try? await eventStore.pendingEvents()
            return pending?.isEmpty == true
        }
        let requestsAfterDeadline = await provider.requests
        XCTAssertEqual(requestsAfterDeadline.count, 1)
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
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
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

    func testInFlightDigestCompactionPreservesClaimedPrefixUntilCommit() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        var policy = TypingEventRetentionPolicy.default
        policy.maximumPendingEventCount = 5
        policy.compactedPendingEventCount = 4
        policy.maximumDigestEventCount = 2
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy
        )
        for index in 0..<5 {
            try await eventStore.append(
                makeContextEvent(rawInput: "raw-\(index)", committedText: "text-\(index)")
            )
        }
        let provider = SuspendedDigestLLMProvider()
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )

        let digest = Task {
            await runtime.processIfNeeded()
        }
        try await waitUntilProviderReceivesRequest(provider)
        await runtime.record(makeContextEvent(rawInput: "raw-5", committedText: "text-5"))
        await provider.finish(generatedMarkdown: "## Global Style\n- Preserved claim.")
        await digest.value

        let environment = try String(contentsOf: environmentURL, encoding: .utf8)
        let pendingEvents = try await eventStore.pendingEvents()
        XCTAssertTrue(environment.contains("Preserved claim"))
        XCTAssertEqual(pendingEvents.map(\.rawInput), ["raw-4", "raw-5"])
    }

    func testProtectedOnlyBatchIsArchivedWithoutProviderDigest() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events", isDirectory: true)
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Normal digest.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
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

        await runtime.record(makeContextEvent(rawInput: "normal", committedText: "普通"))
        let requestsAfterNormalEvent = await provider.requests
        XCTAssertEqual(requestsAfterNormalEvent.count, 1)
        XCTAssertTrue(try eventStore.inventory().eventCount == 0)
    }

    func testProtectedOnlyDigestPrefixStaysLocalWhenBacklogTailIsUnprotected() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        var policy = TypingEventRetentionPolicy.default
        policy.maximumDigestEventCount = 2
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: policy
        )
        for index in 0..<2 {
            try await eventStore.append(
                AITypingEvent(
                    rawInput: "protected:item-\(index)",
                    committedText: "protected:item-\(index)",
                    commitKind: .raw,
                    candidateSource: "protected"
                )
            )
        }
        try await eventStore.append(
            makeContextEvent(rawInput: "normal", committedText: "normal")
        )
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Tail digest.")
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md")
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 3,
            minimumInterval: 1,
            maximumPendingAge: 1,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: clock.now())

        let requests = await provider.requests
        let pendingEvents = try await eventStore.pendingEvents()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(pendingEvents.map(\.rawInput), ["normal"])
        let schedule = try XCTUnwrap(environmentStore.loadDigestScheduleState())
        XCTAssertNil(schedule.lastSuccessfulDigestAt)
        XCTAssertNotNil(schedule.pendingSince)

        clock.advance(by: 2)
        try await waitUntil { !(await provider.requests).isEmpty }
        try await waitUntil { (try? eventStore.inventory().eventCount) == 0 }
        let requestsAfterTailDigest = await provider.requests
        XCTAssertEqual(requestsAfterTailDigest.count, 1)
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
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
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
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
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
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
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

    func testMultipartDigestResponseIsRejectedWithoutCommittingPendingEvents() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events", isDirectory: true)
        )
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        let originalEnvironment = try environmentStore.loadSnapshot().content
        let gate = ProviderRequestGate()
        let provider = MultipartDigestLLMProvider(parts: [
            "## Global Style",
            "- Uses concise text.",
            "## App Habits",
            "- TextEdit: writes short notes."
        ])
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: gate
        )

        await runtime.record(
            AITypingEvent(
                rawInput: "nihao",
                committedText: "你好",
                commitKind: .traditional,
                candidateSource: "traditional"
            )
        )

        let environment = try environmentStore.loadSnapshot().content
        let pendingEvents = try await eventStore.pendingEvents()
        let cooldown = await gate.cooldownDeadline(
            providerIdentity: provider.providerName,
            generation: 0
        )

        XCTAssertEqual(environment, originalEnvironment)
        XCTAssertEqual(pendingEvents.map(\.rawInput), ["nihao"])
        XCTAssertNotNil(cooldown)
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
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
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
        let clock = ManualContextClock()
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
            minimumInterval: 600,
            nowProvider: clock.now
        )

        await runtime.record(makeContextEvent(rawInput: "nihao", committedText: "你好"))
        clock.advance(by: 600)
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

    func testContextGenerationChangeCoalescesInFlightSignalsAndRerunsPendingEvents() async throws {
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
        let registry = makeRegistry(source: source, signal: signal)
        let runtime = AIContextMemoryRuntime(
            providerRegistry: registry,
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
        await runtime.record(makeContextEvent(rawInput: "mingtian", committedText: "明天"))
        await runtime.processIfNeeded()
        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        signal.send(2)
        try await waitUntil { await registry.currentGeneration() == 2 }
        let cancellationCount = await providerA.cancellationCount
        XCTAssertEqual(cancellationCount, 0)
        await providerA.finish(responseText: "## Global Style\n- Provider A stale digest.")
        await oldDigest.value
        try await waitUntil {
            guard await providerB.requestCount == 1 else { return false }
            let pending = try? await eventStore.pendingEvents()
            guard pending?.isEmpty == true else { return false }
            let environment = try? String(contentsOf: environmentURL, encoding: .utf8)
            return environment?.contains("Provider B digest") == true
        }

        let pendingAfterRetry = try await eventStore.pendingEvents()
        let currentEnvironment = try String(contentsOf: environmentURL, encoding: .utf8)
        let providerBRequests = await providerB.recordedRequests
        XCTAssertTrue(pendingAfterRetry.isEmpty)
        XCTAssertTrue(currentEnvironment.contains("Provider B digest"))
        XCTAssertEqual(providerBRequests.count, 1)
        XCTAssertTrue(providerBRequests[0].rawInput?.contains("nihao") == true)
        XCTAssertTrue(providerBRequests[0].rawInput?.contains("zaijian") == true)
        XCTAssertTrue(providerBRequests[0].rawInput?.contains("mingtian") == true)
    }

    func testRegistryStaleBeforeGuardedCommitDoesNotCreateOrphanClaim() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let providerA = NamedLLMProvider(
            name: "provider-a",
            responseText: "## Global Style\n- stale"
        )
        let providerB = NamedLLMProvider(
            name: "provider-b",
            responseText: "## Global Style\n- current"
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: providerA
        )
        let probe = AIContextMemoryRuntimeTestProbe(pausesBeforeGuardedCommit: true)
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source),
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600,
            testProbe: probe
        )

        let staleDigest = Task {
            await runtime.record(makeContextEvent(rawInput: "old", committedText: "旧"))
        }
        try await waitUntil { await probe.guardedCommitPauseCount == 1 }
        let claimURL = directory.appendingPathComponent("ENV.digest-claim.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path))

        source.set(
            revision: 2,
            fingerprint: String(repeating: "b", count: 64),
            provider: providerB
        )
        await probe.releaseGuardedCommit()
        await staleDigest.value

        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path))
        let pendingAfterStale = try await eventStore.pendingEvents()
        XCTAssertEqual(pendingAfterStale.map(\.rawInput), ["old"])

        await runtime.processIfNeeded()

        let providerARequestCount = await providerA.requestCount
        let providerBRequestCount = await providerB.requestCount
        let pendingAfterRetry = try await eventStore.pendingEvents()
        XCTAssertEqual(providerARequestCount, 1)
        XCTAssertEqual(providerBRequestCount, 1)
        XCTAssertTrue(pendingAfterRetry.isEmpty)
        let environment = try String(contentsOf: environmentURL, encoding: .utf8)
        XCTAssertTrue(environment.contains("current"))
        XCTAssertFalse(environment.contains("stale"))
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
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: probe
        )
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
        try await waitUntil { await providerB.requestCount == 1 }

        let providerARequestCount = await providerA.requestCount
        XCTAssertEqual(providerARequestCount, 1)
        let providerBRequests = await providerB.recordedRequests
        XCTAssertEqual(providerBRequests.count, 1)
        guard let request = providerBRequests.first else {
            XCTFail("Provider B did not record a recovery digest request")
            return
        }
        XCTAssertTrue(request.rawInput?.contains("nihao") == true)
        XCTAssertTrue(request.rawInput?.contains("zaijian") == true)
        let pendingEvents = try await eventStore.pendingEvents()
        XCTAssertTrue(pendingEvents.isEmpty)
        XCTAssertEqual(probe.digestSnapshotDecodeCount, 2)
    }

    func testInventoryDefersSnapshotDecodeUntilFiftiethEvent() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: .default,
            testProbe: probe
        )
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Bounded digest.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 50,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )

        for index in 0..<49 {
            await runtime.record(makeContextEvent(rawInput: "raw-\(index)", committedText: "text-\(index)"))
        }

        XCTAssertEqual(probe.inventoryScanCount, 1)
        XCTAssertEqual(probe.digestSnapshotDecodeCount, 0)
        let requestsBeforeThreshold = await provider.requests
        XCTAssertTrue(requestsBeforeThreshold.isEmpty)

        await runtime.record(makeContextEvent(rawInput: "raw-49", committedText: "text-49"))

        XCTAssertEqual(probe.digestSnapshotDecodeCount, 1)
        let requestsAfterThreshold = await provider.requests
        XCTAssertEqual(requestsAfterThreshold.count, 1)
    }

    func testFailureCooldownAppendsOneHundredEventsWithoutAnotherSnapshotDecode() async throws {
        let directory = makeTemporaryDirectory()
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: probe
        )
        let diagnostics = ContextMemoryDiagnosticProbe()
        let provider = FailingDigestLLMProvider()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600,
            diagnosticSink: diagnostics.record,
            requestGate: ProviderRequestGate()
        )

        await runtime.record(makeContextEvent(rawInput: "first", committedText: "first-text"))
        for index in 0..<100 {
            await runtime.record(makeContextEvent(rawInput: "raw-\(index)", committedText: "text-\(index)"))
        }

        let requestCount = await provider.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(probe.digestSnapshotDecodeCount, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 101)
        XCTAssertEqual(diagnostics.stageCount("context_digest_deferred"), 1)
    }

    func testPendingRetentionKeepsLatestEventsAndTruncatesUnicodeScalars() async throws {
        let directory = makeTemporaryDirectory()
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: probe
        )
        for index in 0..<500 {
            _ = try eventStore.appendBounded(
                makeContextEvent(rawInput: "raw-\(index)", committedText: "text-\(index)")
            )
        }
        let oversized = String(repeating: "界", count: 3_000)

        let result = try eventStore.appendBounded(
            makeContextEvent(rawInput: oversized, committedText: oversized)
        )
        let events = try await eventStore.pendingEvents()

        XCTAssertEqual(result.truncatedScalarCount, 1_904)
        XCTAssertEqual(result.droppedEventCount, 51)
        XCTAssertEqual(events.count, 450)
        XCTAssertEqual(events.first?.rawInput, "raw-51")
        XCTAssertEqual(events.last?.rawInput?.unicodeScalars.count, 2_048)
        XCTAssertLessThanOrEqual(result.inventory.byteCount, 786_432)
        XCTAssertEqual(probe.atomicRewriteCount, 1)
    }

    func testPendingByteRetentionRewritesAtomicallyWithinTarget() async throws {
        let directory = makeTemporaryDirectory()
        let probe = TypingEventStoreTestProbe()
        var policy = TypingEventRetentionPolicy.default
        policy.maximumPendingByteCount = 1_800
        policy.compactedPendingByteCount = 900
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: policy,
            testProbe: probe
        )

        for index in 0..<20 {
            _ = try eventStore.appendBounded(
                makeContextEvent(
                    rawInput: "raw-\(index)-" + String(repeating: "x", count: 100),
                    committedText: "text-\(index)-" + String(repeating: "y", count: 100)
                )
            )
        }

        let inventory = try eventStore.inventory()
        let events = try await eventStore.pendingEvents()
        XCTAssertLessThanOrEqual(inventory.byteCount, policy.maximumPendingByteCount)
        XCTAssertGreaterThan(probe.atomicRewriteCount, 0)
        XCTAssertEqual(events.last?.rawInput?.hasPrefix("raw-19-"), true)
        XCTAssertEqual(events.map(\.timestamp), events.map(\.timestamp).sorted())
    }

    func testOversizedMetadataIsTruncatedBeforePendingRetention() async throws {
        let directory = makeTemporaryDirectory()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default
        )
        let oversized = String(repeating: "界", count: 300_000)

        let result = try eventStore.appendBounded(
            AITypingEvent(
                appBundleID: oversized,
                appName: oversized,
                rawInput: "raw",
                committedText: "text",
                commitKind: .traditional,
                candidateSource: oversized
            )
        )
        let pendingEvents = try await eventStore.pendingEvents()
        let event = try XCTUnwrap(pendingEvents.first)
        let snapshot = try eventStore.pendingDigestSnapshot()

        XCTAssertEqual(event.appBundleID?.unicodeScalars.count, 2_048)
        XCTAssertEqual(event.appName?.unicodeScalars.count, 2_048)
        XCTAssertEqual(event.candidateSource.unicodeScalars.count, 2_048)
        XCTAssertEqual(result.truncatedScalarCount, 893_856)
        XCTAssertLessThanOrEqual(result.inventory.byteCount, 786_432)
        XCTAssertLessThanOrEqual(snapshot.requestData.count, 48 * 1_024)
    }

    func testDigestClaimsAtMostFiftyEventsAndLeavesBacklogTailPending() async throws {
        let directory = makeTemporaryDirectory()
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: probe
        )
        for index in 0..<75 {
            try await eventStore.append(
                makeContextEvent(rawInput: "raw-\(index)", committedText: "text-\(index)")
            )
        }
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Prefix only.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 50,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )

        await runtime.processIfNeeded()

        let requests = await provider.requests
        let requestData = Data((try XCTUnwrap(requests.first?.rawInput)).utf8)
        let pendingEvents = try await eventStore.pendingEvents()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].rawInput?.split(whereSeparator: \.isNewline).count, 50)
        XCTAssertLessThanOrEqual(requestData.count, 48 * 1_024)
        XCTAssertEqual(pendingEvents.count, 25)
        XCTAssertEqual(pendingEvents.first?.rawInput, "raw-50")
        XCTAssertEqual(probe.digestSnapshotDecodeCount, 1)
    }

    func testInventoryRecoversOnceAfterProcessRestartAndToleratesCorruptLine() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let firstStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        try await firstStore.append(makeContextEvent(rawInput: "one", committedText: "一"))
        try await firstStore.append(makeContextEvent(rawInput: "two", committedText: "二"))
        let eventsFile = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        let handle = try FileHandle(forWritingTo: eventsFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"incomplete\":\n".utf8))
        try handle.close()

        TypingEventStore.resetInventoryCacheForTesting(eventsDirectoryURL: eventsDirectory)
        let probe = TypingEventStoreTestProbe()
        let recoveredStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: .default,
            testProbe: probe
        )

        XCTAssertEqual(try recoveredStore.inventory().eventCount, 3)
        XCTAssertEqual(try recoveredStore.inventory().eventCount, 3)
        XCTAssertEqual(probe.inventoryScanCount, 1)
        let snapshot = try recoveredStore.pendingDigestSnapshot()
        XCTAssertEqual(snapshot.claimedEventCount, 3)
        XCTAssertEqual(snapshot.events.count, 2)
        XCTAssertFalse(snapshot.requestContent.contains("incomplete"))
    }

    func testOversizedLegacyRecordIsArchivedLocallyInsteadOfSentToProvider() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var legacyLine = try encoder.encode(
            makeContextEvent(
                rawInput: String(repeating: "x", count: 300_000),
                committedText: "legacy"
            )
        )
        legacyLine.append(0x0A)
        try legacyLine.write(to: eventsDirectory.appendingPathComponent("typing-events.jsonl"))
        TypingEventStore.resetInventoryCacheForTesting(eventsDirectoryURL: eventsDirectory)
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let snapshot = try eventStore.pendingDigestSnapshot()
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Must not run.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )

        await runtime.processIfNeeded()

        let requests = await provider.requests
        XCTAssertEqual(snapshot.rawData.count, 48 * 1_024)
        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertLessThanOrEqual(snapshot.requestData.count, 48 * 1_024)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
    }

    func testBlankDigestPrefixIsArchivedWithoutStartingFailureCooldown() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let eventsDirectory = directory.appendingPathComponent("events")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var pendingData = Data(repeating: 0x0A, count: 50)
        var validLine = try encoder.encode(
            makeContextEvent(rawInput: "valid", committedText: "有效")
        )
        validLine.append(0x0A)
        pendingData.append(validLine)
        try pendingData.write(to: eventsDirectory.appendingPathComponent("typing-events.jsonl"))
        TypingEventStore.resetInventoryCacheForTesting(eventsDirectoryURL: eventsDirectory)
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Recovered.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 2,
            minimumInterval: 1,
            maximumPendingAge: 1,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: clock.now())

        let requestsAfterRecovery = await provider.requests
        XCTAssertTrue(requestsAfterRecovery.isEmpty)
        XCTAssertEqual(try eventStore.inventory().eventCount, 1)

        clock.advance(by: 2)
        try await waitUntil { !(await provider.requests).isEmpty }
        try await waitUntil { (try? eventStore.inventory().eventCount) == 0 }

        let requestsAfterDigest = await provider.requests
        XCTAssertEqual(requestsAfterDigest.count, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
    }

    func testOversizedDigestPrefixWithTailRearmsDeadlineWithoutNewInput() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let eventsDirectory = directory.appendingPathComponent("events")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var oversizedLine = try encoder.encode(
            makeContextEvent(
                rawInput: String(repeating: "x", count: 300_000),
                committedText: "legacy"
            )
        )
        oversizedLine.append(0x0A)
        var tailLine = try encoder.encode(makeContextEvent(rawInput: "tail", committedText: "尾部"))
        tailLine.append(0x0A)
        oversizedLine.append(tailLine)
        try oversizedLine.write(to: eventsDirectory.appendingPathComponent("typing-events.jsonl"))
        TypingEventStore.resetInventoryCacheForTesting(eventsDirectoryURL: eventsDirectory)

        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Recovered tail.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 2,
            minimumInterval: 1,
            maximumPendingAge: 1,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: clock.now())

        let requestsBeforeDeadline = await provider.requests
        let pendingBeforeDeadline = try await eventStore.pendingEvents()
        XCTAssertTrue(requestsBeforeDeadline.isEmpty)
        XCTAssertEqual(pendingBeforeDeadline.map(\.rawInput), ["tail"])

        clock.advance(by: 2)
        try await waitUntil { !(await provider.requests).isEmpty }
        try await waitUntil { (try? eventStore.inventory().eventCount) == 0 }
        let requestsAfterDeadline = await provider.requests
        XCTAssertEqual(requestsAfterDeadline.count, 1)
    }

    func testOversizedNewlineLessRecordUsesBoundedDigestClaim() throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        let policy = TypingEventRetentionPolicy.default
        try Data(repeating: 0x78, count: 400_000).write(
            to: eventsDirectory.appendingPathComponent("typing-events.jsonl")
        )
        TypingEventStore.resetInventoryCacheForTesting(eventsDirectoryURL: eventsDirectory)
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            testProbe: probe
        )

        let snapshot = try eventStore.pendingDigestSnapshot()

        XCTAssertEqual(snapshot.rawData.count, policy.maximumDigestByteCount)
        XCTAssertEqual(snapshot.claimedEventCount, 1)
        XCTAssertTrue(snapshot.events.isEmpty)
        XCTAssertLessThanOrEqual(
            probe.maximumBufferedReadByteCount,
            policy.maximumDigestByteCount
        )
    }

    func testFirstAppendCompactsOversizedLegacyBacklogWithBoundedRead() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var legacyData = Data()
        for index in 0..<700 {
            var line = try encoder.encode(
                makeContextEvent(
                    rawInput: "legacy-\(index)-" + String(repeating: "x", count: 4_096),
                    committedText: "text-\(index)"
                )
            )
            line.append(0x0A)
            legacyData.append(line)
        }
        XCTAssertGreaterThan(legacyData.count, TypingEventRetentionPolicy.default.maximumPendingByteCount)
        try legacyData.write(to: eventsDirectory.appendingPathComponent("typing-events.jsonl"))
        TypingEventStore.resetInventoryCacheForTesting(eventsDirectoryURL: eventsDirectory)
        let policy = TypingEventRetentionPolicy.default
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            testProbe: probe
        )

        let result = try eventStore.appendBounded(
            makeContextEvent(rawInput: "newest", committedText: "最新")
        )
        let events = try await eventStore.pendingEvents()

        XCTAssertLessThanOrEqual(result.inventory.eventCount, policy.compactedPendingEventCount + 1)
        XCTAssertLessThanOrEqual(result.inventory.byteCount, policy.maximumPendingByteCount)
        XCTAssertEqual(events.last?.rawInput, "newest")
        XCTAssertEqual(probe.inventoryScanCount, 1)
        XCTAssertEqual(probe.atomicRewriteCount, 1)
        XCTAssertLessThanOrEqual(
            probe.maximumBufferedReadByteCount,
            policy.compactedPendingByteCount
        )
    }

    func testInventoryRescansAfterSameSizeAtomicFileReplacement() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: .default,
            testProbe: probe
        )
        try await eventStore.append(makeContextEvent(rawInput: "one", committedText: "one"))
        _ = try eventStore.inventory()
        let eventsFile = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: eventsFile.path)
        let originalData = try Data(contentsOf: eventsFile)
        let originalText = try XCTUnwrap(String(data: originalData, encoding: .utf8))
        let replacementData = Data(originalText.replacingOccurrences(of: "one", with: "two").utf8)
        XCTAssertEqual(replacementData.count, originalData.count)
        try replacementData.write(to: eventsFile, options: .atomic)
        if let modificationDate = originalAttributes[.modificationDate] {
            try FileManager.default.setAttributes(
                [.modificationDate: modificationDate],
                ofItemAtPath: eventsFile.path
            )
        }

        XCTAssertEqual(try eventStore.inventory().eventCount, 1)
        XCTAssertEqual(probe.inventoryScanCount, 2)
        let pendingEvents = try await eventStore.pendingEvents()
        XCTAssertEqual(pendingEvents.first?.rawInput, "two")
    }

    func testTypingEventFilesRemainPrivateAcrossAppendArchiveAndCompaction() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let eventsURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        var policy = TypingEventRetentionPolicy.default
        policy.maximumPendingEventCount = 2
        policy.compactedPendingEventCount = 2
        policy.maximumDigestEventCount = 1
        let store = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy
        )

        try await store.append(makeContextEvent(rawInput: "one", committedText: "一"))
        var permissions = try FileManager.default.attributesOfItem(
            atPath: eventsURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: eventsURL.path
        )
        try await store.append(makeContextEvent(rawInput: "two", committedText: "二"))
        permissions = try FileManager.default.attributesOfItem(
            atPath: eventsURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        let snapshot = try store.pendingDigestSnapshot()
        _ = try store.commitPendingEvents(matching: snapshot, beforeArchive: {})
        permissions = try FileManager.default.attributesOfItem(
            atPath: eventsURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        let processedDirectory = eventsDirectory.appendingPathComponent("processed")
        let archives = try FileManager.default.contentsOfDirectory(
            at: processedDirectory,
            includingPropertiesForKeys: nil
        )
        let archiveURL = try XCTUnwrap(archives.first)
        permissions = try FileManager.default.attributesOfItem(
            atPath: archiveURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: archiveURL.path
        )
        let prefixHash = archiveURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "typing-events-", with: "")
        XCTAssertEqual(
            store.processedArchiveValidation(
                prefixSHA256: prefixHash,
                byteCount: snapshot.rawData.count
            ),
            .valid
        )
        permissions = try FileManager.default.attributesOfItem(
            atPath: archiveURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        try await store.append(makeContextEvent(rawInput: "three", committedText: "三"))
        try await store.append(makeContextEvent(rawInput: "four", committedText: "四"))
        permissions = try FileManager.default.attributesOfItem(
            atPath: eventsURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertEqual(try store.inventory().eventCount, 2)
    }

    func testTypingEventPermissionFailureFailsClosedBeforePendingCreation() throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let probe = TypingEventStoreTestProbe()
        probe.failNextPermissionChanges(1)
        let store = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: .default,
            testProbe: probe
        )

        XCTAssertThrowsError(
            try store.appendBounded(makeContextEvent(rawInput: "private", committedText: "私密"))
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: eventsDirectory.appendingPathComponent("typing-events.jsonl").path
            )
        )
    }

    func testProtectedOnlyInventoryArchivesWithoutDigestSnapshotOrProviderRead() async throws {
        let directory = makeTemporaryDirectory()
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: probe
        )
        try await eventStore.append(
            AITypingEvent(
                rawInput: "protected:redacted",
                committedText: "protected:redacted",
                commitKind: .raw,
                candidateSource: "protected"
            )
        )
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

        await runtime.processIfNeeded()

        XCTAssertEqual(source.revisionReadCount, 0)
        XCTAssertEqual(probe.digestSnapshotDecodeCount, 0)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
    }

    func testProtectedOnlyInventoryIgnoresCorruptLineWithoutProviderRead() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: .default,
            testProbe: probe
        )
        try await eventStore.append(
            AITypingEvent(
                rawInput: "protected:redacted",
                committedText: "protected:redacted",
                commitKind: .raw,
                candidateSource: "protected"
            )
        )
        let eventsFile = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        let handle = try FileHandle(forWritingTo: eventsFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"incomplete\":\n".utf8))
        try handle.close()
        TypingEventStore.resetInventoryCacheForTesting(eventsDirectoryURL: eventsDirectory)
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

        await runtime.processIfNeeded()

        XCTAssertEqual(source.revisionReadCount, 0)
        XCTAssertEqual(probe.digestSnapshotDecodeCount, 0)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
    }

    func testProcessedRetentionEnforcesAgeCountAndBytesAfterSuccessfulDigest() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let processedDirectory = eventsDirectory.appendingPathComponent("processed")
        try FileManager.default.createDirectory(at: processedDirectory, withIntermediateDirectories: true)
        let fixedNow = Date()
        let expiredURL = processedDirectory.appendingPathComponent("typing-events-expired.jsonl")
        try Data(repeating: 0x61, count: 50).write(to: expiredURL)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedNow.addingTimeInterval(-8 * 24 * 60 * 60)],
            ofItemAtPath: expiredURL.path
        )
        for index in 0..<5 {
            let url = processedDirectory.appendingPathComponent("typing-events-current-\(index).jsonl")
            try Data(repeating: UInt8(0x62 + index), count: 100).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: fixedNow.addingTimeInterval(TimeInterval(index))],
                ofItemAtPath: url.path
            )
        }
        var policy = TypingEventRetentionPolicy.default
        policy.processedMaximumFileCount = 3
        policy.processedMaximumByteCount = 250
        let diagnostics = ContextMemoryDiagnosticProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            now: { fixedNow }
        )
        let runtime = AIContextMemoryRuntime(
            provider: DigestLLMProvider(generatedMarkdown: "## Global Style\n- Retained."),
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600,
            diagnosticSink: diagnostics.record,
            requestGate: ProviderRequestGate()
        )

        await runtime.record(makeContextEvent(rawInput: "retention", committedText: "保留"))

        let archives = try FileManager.default.contentsOfDirectory(
            at: processedDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        let totalBytes = try archives.reduce(0) { partial, url in
            partial + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredURL.path))
        XCTAssertLessThanOrEqual(archives.count, 3)
        XCTAssertLessThanOrEqual(totalBytes, 250)
        XCTAssertEqual(diagnostics.stageCount("context_archive_pruned"), 1)
        XCTAssertEqual(TypingEventRetentionPolicy.default.processedMaximumAge, 7 * 24 * 60 * 60)
        XCTAssertEqual(TypingEventRetentionPolicy.default.processedMaximumFileCount, 100)
        XCTAssertEqual(TypingEventRetentionPolicy.default.processedMaximumByteCount, 10 * 1_048_576)
    }

    func testProcessedPruneFailureDoesNotUndoSuccessfulDigest() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let processedDirectory = eventsDirectory.appendingPathComponent("processed")
        try FileManager.default.createDirectory(at: processedDirectory, withIntermediateDirectories: true)
        let fixedNow = Date()
        let oldArchive = processedDirectory.appendingPathComponent("typing-events-old.jsonl")
        try Data(repeating: 0x61, count: 100).write(to: oldArchive)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedNow.addingTimeInterval(-8 * 24 * 60 * 60)],
            ofItemAtPath: oldArchive.path
        )
        var policy = TypingEventRetentionPolicy.default
        policy.processedMaximumFileCount = 1
        let probe = TypingEventStoreTestProbe()
        probe.failNextArchiveDeletions(10)
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            testProbe: probe,
            now: { fixedNow }
        )
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- Completed.")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )

        await runtime.record(makeContextEvent(rawInput: "success", committedText: "成功"))

        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
        XCTAssertTrue(try String(contentsOf: environmentURL, encoding: .utf8).contains("Completed"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldArchive.path))
        let providerRequests = await provider.requests
        XCTAssertEqual(providerRequests.count, 1)
        XCTAssertNil(try environmentStore.loadDigestClaim())
    }

    func testProcessedPruneFailurePreservesCurrentClaimRecoveryArchive() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let processedDirectory = eventsDirectory.appendingPathComponent("processed")
        try FileManager.default.createDirectory(at: processedDirectory, withIntermediateDirectories: true)
        let tiedModificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let fixedNow = tiedModificationDate.addingTimeInterval(1)
        let oldArchives = (0..<2).map { index in
            processedDirectory.appendingPathComponent("typing-events-!!old-\(index).jsonl")
        }
        for (index, url) in oldArchives.enumerated() {
            try Data(repeating: UInt8(0x61 + index), count: 100).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: tiedModificationDate],
                ofItemAtPath: url.path
            )
        }

        var policy = TypingEventRetentionPolicy.default
        policy.processedMaximumAge = 0
        policy.processedMaximumFileCount = 1
        policy.processedMaximumByteCount = 1
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            testProbe: probe,
            now: { fixedNow }
        )
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        let generated = "## Global Style\n- committed before recovery"
        try await eventStore.append(
            makeContextEvent(rawInput: "claimed", committedText: "已声明")
        )
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        let claimedPrefixSHA256 = AIDocumentSnapshot.hash(claimedSnapshot.rawContent)
        let destination = processedDirectory.appendingPathComponent(
            "typing-events-\(claimedPrefixSHA256).jsonl"
        )
        _ = try environmentStore.replaceGeneratedSection(with: generated)
        try environmentStore.saveDigestClaim(
            EnvironmentDigestClaim(
                claimedPrefixSHA256: claimedPrefixSHA256,
                claimedPrefixByteCount: claimedSnapshot.rawData.count,
                claimedEventCount: claimedSnapshot.claimedEventCount,
                generatedSHA256: AIDocumentSnapshot.hash(generated),
                providerGeneration: 0
            )
        )
        try await eventStore.append(
            makeContextEvent(rawInput: "tail", committedText: "尾部")
        )
        probe.forceNextProcessedArchiveModificationDate(tiedModificationDate)
        probe.failNextArchiveDeletions(oldArchives.count)

        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: { fixedNow }
        )

        await runtime.processIfNeeded(now: fixedNow)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(
            eventStore.processedArchiveValidation(
                prefixSHA256: claimedPrefixSHA256,
                byteCount: claimedSnapshot.rawData.count
            ),
            .valid
        )
        XCTAssertTrue(oldArchives.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let pending = try await eventStore.pendingEvents()
        XCTAssertEqual(pending.map(\.rawInput), ["tail"])
        XCTAssertNil(try environmentStore.loadDigestClaim())
        let providerRequests = await provider.requests
        XCTAssertTrue(providerRequests.isEmpty)

        let retainedArchives = try FileManager.default.contentsOfDirectory(
            at: processedDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ).filter { $0.lastPathComponent.hasPrefix("typing-events-") }
        let retainedBytes = try retainedArchives.reduce(0) { partial, url in
            partial + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        let retainedModificationDates = try retainedArchives.map { url in
            try XCTUnwrap(
                url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            )
        }
        XCTAssertEqual(retainedArchives.count, 3)
        XCTAssertGreaterThan(retainedArchives.count, policy.processedMaximumFileCount)
        XCTAssertGreaterThan(retainedBytes, policy.processedMaximumByteCount)
        XCTAssertTrue(retainedModificationDates.allSatisfy { $0 == tiedModificationDate })
    }

    func testProtectedOnlyLocalArchivesApplyRetentionWithoutProviderParticipation() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let processedDirectory = eventsDirectory.appendingPathComponent("processed")
        let fixedNow = Date()
        var policy = TypingEventRetentionPolicy.default
        policy.processedMaximumFileCount = 3
        policy.processedMaximumByteCount = 768
        let seededArchives = try seedProcessedRetentionArchives(
            at: processedDirectory,
            now: fixedNow
        )
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            now: { fixedNow }
        )
        let provider = FailingDigestLLMProvider()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: { fixedNow }
        )

        for index in 0..<8 {
            await runtime.record(
                AITypingEvent(
                    rawInput: "protected:item-\(index)",
                    committedText: "protected:item-\(index)",
                    commitKind: .raw,
                    candidateSource: "protected"
                )
            )
        }

        let archives = try FileManager.default.contentsOfDirectory(
            at: processedDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.lastPathComponent.hasPrefix("typing-events-") }
        let totalBytes = try archives.reduce(0) { partial, url in
            partial + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        let pendingEvents = try await eventStore.pendingEvents()
        let providerRequestCount = await provider.requestCount

        XCTAssertEqual(providerRequestCount, 0)
        XCTAssertTrue(pendingEvents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: seededArchives.expired.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: seededArchives.oldestRecent.path))
        XCTAssertGreaterThan(archives.count, 0)
        XCTAssertLessThanOrEqual(archives.count, policy.processedMaximumFileCount)
        XCTAssertLessThanOrEqual(totalBytes, policy.processedMaximumByteCount)
    }

    func testInvalidAndOversizedLocalArchiveRoutesApplyRetention() async throws {
        let routes = ["blank", "undecodable", "unsendable", "empty request content", "oversized"]

        for route in routes {
            let directory = makeTemporaryDirectory()
            let eventsDirectory = directory.appendingPathComponent("events")
            let processedDirectory = eventsDirectory.appendingPathComponent("processed")
            let fixedNow = Date()
            var policy = TypingEventRetentionPolicy.default
            policy.processedMaximumFileCount = 2
            policy.processedMaximumByteCount = route == "oversized" ? 400_000 : 4_096
            policy.maximumDigestEventCount = 2
            let seededArchives = try seedProcessedRetentionArchives(
                at: processedDirectory,
                now: fixedNow
            )
            let eventStore = TypingEventStore(
                eventsDirectoryURL: eventsDirectory,
                retentionPolicy: policy,
                now: { fixedNow }
            )

            let writtenPendingData: Data?
            if route == "empty request content" {
                try await eventStore.append(
                    makeContextEvent(rawInput: "empty-request", committedText: "空请求")
                )
                writtenPendingData = nil
            } else {
                let pendingData: Data
                switch route {
                case "blank":
                    pendingData = Data(repeating: 0x0A, count: 2)
                case "undecodable":
                    pendingData = Data("{\"incomplete\":\n".utf8)
                case "unsendable":
                    pendingData = Data([0xFF, 0xFE, 0xFD, 0x0A])
                case "oversized":
                    var line = try JSONEncoder().encode(
                        makeContextEvent(
                            rawInput: String(repeating: "x", count: 300_000),
                            committedText: "legacy"
                        )
                    )
                    line.append(0x0A)
                    pendingData = line
                default:
                    XCTFail("unhandled local archive route: \(route)")
                    continue
                }
                try pendingData.write(
                    to: eventsDirectory.appendingPathComponent("typing-events.jsonl")
                )
                TypingEventStore.resetInventoryCacheForTesting(eventsDirectoryURL: eventsDirectory)
                writtenPendingData = pendingData
            }

            let decodedSnapshot = try eventStore.pendingDigestSnapshot()
            let snapshot: TypingEventSnapshot
            if route == "empty request content" {
                snapshot = TypingEventSnapshot(
                    rawData: decodedSnapshot.rawData,
                    requestData: Data(),
                    events: decodedSnapshot.events,
                    claimedEventCount: decodedSnapshot.claimedEventCount
                )
            } else {
                snapshot = decodedSnapshot
            }
            XCTAssertTrue(snapshot.requestContent.isEmpty, route)
            if route == "empty request content" {
                XCTAssertEqual(snapshot.events, decodedSnapshot.events, route)
                XCTAssertEqual(snapshot.events.count, 1, route)
            } else {
                XCTAssertTrue(snapshot.events.isEmpty, route)
            }
            let expectedArchiveData = writtenPendingData ?? snapshot.rawData
            let expectedArchiveSHA256 = rawDataSHA256(expectedArchiveData)

            try eventStore.archivePendingEvents(matching: snapshot)

            let archives = try FileManager.default.contentsOfDirectory(
                at: processedDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            ).filter { $0.lastPathComponent.hasPrefix("typing-events-") }
            let totalBytes = try archives.reduce(0) { partial, url in
                partial + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
            let pendingEvents = try await eventStore.pendingEvents()
            let archiveURL = processedDirectory.appendingPathComponent(
                "typing-events-\(expectedArchiveSHA256).jsonl"
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path), route)
            XCTAssertEqual(try Data(contentsOf: archiveURL), expectedArchiveData, route)
            XCTAssertTrue(
                eventStore.hasProcessedArchive(
                    prefixSHA256: expectedArchiveSHA256,
                    byteCount: expectedArchiveData.count
                ),
                route
            )
            XCTAssertTrue(pendingEvents.isEmpty, route)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: eventsDirectory.appendingPathComponent("typing-events.jsonl").path
                ),
                route
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: seededArchives.expired.path),
                route
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: seededArchives.oldestRecent.path),
                route
            )
            XCTAssertLessThanOrEqual(archives.count, policy.processedMaximumFileCount, route)
            XCTAssertLessThanOrEqual(totalBytes, policy.processedMaximumByteCount, route)
        }
    }

    func testArchiveFailureWithAppendedTailRecoversClaimPrefixWithoutProviderRetry() async throws {
        let directory = makeTemporaryDirectory()
        let probe = TypingEventStoreTestProbe()
        probe.failNextPendingArchives(1)
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: probe
        )
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- recovered")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )

        await runtime.record(makeContextEvent(rawInput: "claimed", committedText: "已 claim"))
        let firstRequestCount = await provider.requests.count
        XCTAssertEqual(firstRequestCount, 1)
        try await eventStore.append(makeContextEvent(rawInput: "tail", committedText: "尾部"))

        await runtime.processIfNeeded()

        let recoveredRequestCount = await provider.requests.count
        XCTAssertEqual(recoveredRequestCount, 1)
        let pending = try await eventStore.pendingEvents()
        XCTAssertEqual(pending.map(\.rawInput), ["tail"])
    }

    func testTruncationDiagnosticContainsLengthsButNoOriginalText() async throws {
        let directory = makeTemporaryDirectory()
        let diagnostics = ContextMemoryDiagnosticProbe()
        let runtime = AIContextMemoryRuntime(
            provider: nil,
            eventStore: TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events")),
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 50,
            minimumInterval: 600,
            diagnosticSink: diagnostics.record,
            requestGate: ProviderRequestGate()
        )
        let sensitive = "sensitive-sentinel-" + String(repeating: "界", count: 3_000)

        await runtime.record(makeContextEvent(rawInput: sensitive, committedText: sensitive))

        let line = try XCTUnwrap(diagnostics.lines.first)
        XCTAssertTrue(line.contains("stage=context_event_truncated"))
        XCTAssertTrue(line.contains("truncatedScalarCount="))
        XCTAssertFalse(line.contains("sensitive-sentinel"))
    }

    func testBatchThresholdCannotBypassMinimumIntervalAfterSuccessfulDigest() async throws {
        let directory = makeTemporaryDirectory()
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- bounded")
        let eventStore = TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events"))
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )

        await runtime.record(makeContextEvent(rawInput: "first", committedText: "第一"))
        try await eventStore.append(makeContextEvent(rawInput: "second", committedText: "第二"))
        await runtime.processIfNeeded(now: Date().addingTimeInterval(1))

        let requestCount = await provider.requests.count
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 1)
    }

    func testDigestCadenceSurvivesClockRollbackInProcessAndAcrossRestart() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let sixHours: TimeInterval = 6 * 60 * 60
        let oneDay: TimeInterval = 24 * 60 * 60
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        let firstProvider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- bounded cadence")
        let firstRuntime = AIContextMemoryRuntime(
            provider: firstProvider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: sixHours,
            maximumPendingAge: oneDay,
            digestBudgetWindow: oneDay,
            maximumDigestsPerWindow: 4,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await firstRuntime.record(makeContextEvent(rawInput: "first", committedText: "第一"))
        await firstRuntime.record(makeContextEvent(rawInput: "second", committedText: "第二"))
        let requestsBeforeFirstWindow = await firstProvider.requests
        XCTAssertEqual(requestsBeforeFirstWindow.count, 1)

        clock.advance(by: sixHours)
        await firstRuntime.processIfNeeded(now: clock.now())
        clock.advance(by: sixHours)
        await firstRuntime.record(makeContextEvent(rawInput: "third", committedText: "第三"))
        clock.advance(by: sixHours)
        await firstRuntime.record(makeContextEvent(rawInput: "fourth", committedText: "第四"))
        await firstRuntime.record(makeContextEvent(rawInput: "fifth", committedText: "第五"))

        let requestsBeforeRestart = await firstProvider.requests
        XCTAssertEqual(requestsBeforeRestart.count, 4)
        XCTAssertEqual(try eventStore.inventory().eventCount, 1)
        let persistedSchedule = try XCTUnwrap(environmentStore.loadDigestScheduleState())
        XCTAssertEqual(persistedSchedule.successfulDigestTimestamps.count, 4)
        XCTAssertEqual(persistedSchedule.pendingEventCount, 1)

        clock.advance(by: -(2 * 60 * 60))
        await firstRuntime.processIfNeeded(now: clock.now())
        let requestsAfterInProcessRollback = await firstProvider.requests
        XCTAssertEqual(requestsAfterInProcessRollback.count, 4)
        let loadedInProcessDeadline = await firstRuntime.scheduledDeadlineForTesting()
        let inProcessDeadline = try XCTUnwrap(loadedInProcessDeadline)
        XCTAssertEqual(
            inProcessDeadline.timeIntervalSince(clock.now()),
            8 * 60 * 60,
            accuracy: 0.001
        )

        let restartedProvider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- after window")
        let restartedRuntime = AIContextMemoryRuntime(
            provider: restartedProvider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: sixHours,
            maximumPendingAge: oneDay,
            digestBudgetWindow: oneDay,
            maximumDigestsPerWindow: 4,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await restartedRuntime.processIfNeeded(now: clock.now())
        let requestsImmediatelyAfterRestart = await restartedProvider.requests
        XCTAssertTrue(requestsImmediatelyAfterRestart.isEmpty)
        let loadedRestartedDeadline = await restartedRuntime.scheduledDeadlineForTesting()
        let restartedDeadline = try XCTUnwrap(loadedRestartedDeadline)
        XCTAssertEqual(restartedDeadline, inProcessDeadline)

        clock.advance(by: 8 * 60 * 60 - 1)
        await restartedRuntime.processIfNeeded(now: clock.now())
        let requestsBeforeOriginalWindowEnd = await restartedProvider.requests
        XCTAssertTrue(requestsBeforeOriginalWindowEnd.isEmpty)

        clock.advance(by: 2)
        await restartedRuntime.processIfNeeded(now: clock.now())

        let requestsAfterRollingWindow = await restartedProvider.requests
        XCTAssertEqual(requestsAfterRollingWindow.count, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
    }

    func testDigestProcessesLowVolumePendingAtTwentyFourHourMaximumAge() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let oneDay: TimeInterval = 24 * 60 * 60
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- aged pending")
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events")
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: directory.appendingPathComponent("ENV.md")
            ),
            batchSize: 50,
            minimumInterval: 6 * 60 * 60,
            maximumPendingAge: oneDay,
            digestBudgetWindow: oneDay,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.record(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "aged",
                committedText: "待摘要"
            )
        )
        clock.advance(by: oneDay - 1)
        await runtime.processIfNeeded(now: clock.now())
        let requestsBeforeMaximumAge = await provider.requests
        XCTAssertTrue(requestsBeforeMaximumAge.isEmpty)

        clock.advance(by: 2)
        await runtime.processIfNeeded(now: clock.now())

        let requestsAfterMaximumAge = await provider.requests
        XCTAssertEqual(requestsAfterMaximumAge.count, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
    }

    func testSuccessfulDigestTailUsesOldestRemainingEventForPendingAge() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let now = clock.now()
        let sixHours: TimeInterval = 6 * 60 * 60
        let oneDay: TimeInterval = 24 * 60 * 60
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events")
        )
        for index in 0..<50 {
            try await eventStore.append(
                makeContextEvent(
                    timestamp: now.addingTimeInterval(-oneDay),
                    rawInput: "old-\(index)",
                    committedText: "旧事件\(index)"
                )
            )
        }
        try await eventStore.append(
            makeContextEvent(
                timestamp: now,
                rawInput: "new-tail",
                committedText: "新尾部"
            )
        )
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md")
        )
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- old prefix")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 50,
            minimumInterval: sixHours,
            maximumPendingAge: oneDay,
            digestBudgetWindow: oneDay,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: now)

        let schedule = try XCTUnwrap(environmentStore.loadDigestScheduleState())
        XCTAssertEqual(schedule.pendingSince, now)
        let nextEligibleAt = try XCTUnwrap(schedule.nextEligibleAt)
        XCTAssertEqual(nextEligibleAt.timeIntervalSince(now), oneDay, accuracy: 0.001)
        XCTAssertEqual(try eventStore.inventory().eventCount, 1)

        clock.advance(by: sixHours + 1)
        await runtime.processIfNeeded(now: clock.now())

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 1)
    }

    func testSuccessfulDigestTailWaitsForNextSixHourWindow() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let sixHours: TimeInterval = 6 * 60 * 60
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events")
        )
        for index in 0..<100 {
            try await eventStore.append(
                makeContextEvent(rawInput: "event-\(index)", committedText: "事件\(index)")
            )
        }
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- bounded prefix")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: directory.appendingPathComponent("ENV.md")
            ),
            batchSize: 50,
            minimumInterval: sixHours,
            maximumPendingAge: 24 * 60 * 60,
            digestBudgetWindow: 24 * 60 * 60,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: clock.now())
        await runtime.processIfNeeded(now: clock.now())

        let requestsBeforeNextWindow = await provider.requests
        XCTAssertEqual(requestsBeforeNextWindow.count, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 50)

        clock.advance(by: sixHours + 1)
        await runtime.processIfNeeded(now: clock.now())

        let requestsAfterNextWindow = await provider.requests
        XCTAssertEqual(requestsAfterNextWindow.count, 2)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
    }

    func testLongProviderCooldownDefersDigestWithoutDecodingSnapshot() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: probe
        )
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let gate = ProviderRequestGate(now: clock.now)
        let cooldown: TimeInterval = 85 * 60 * 60
        await gate.recordFailure(
            providerIdentity: provider.providerName,
            generation: 0,
            failure: ProviderRateLimitError(
                retryAfterSeconds: cooldown,
                bodyByteCount: 128
            )
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: directory.appendingPathComponent("ENV.md")
            ),
            batchSize: 1,
            minimumInterval: 6 * 60 * 60,
            requestGate: gate,
            nowProvider: clock.now
        )

        await runtime.record(makeContextEvent(rawInput: "cooldown", committedText: "冷却"))
        await runtime.processIfNeeded(now: clock.now())

        let requestsDuringCooldown = await provider.requests
        XCTAssertTrue(requestsDuringCooldown.isEmpty)
        XCTAssertEqual(probe.digestSnapshotDecodeCount, 0)
        let loadedDeadline = await runtime.scheduledDeadlineForTesting()
        let deadline = try XCTUnwrap(loadedDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(clock.now()), cooldown, accuracy: 0.001)
    }

    func testRateLimitFailureImmediatelySchedulesTheFullGateDeadline() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: probe
        )
        let cooldown: TimeInterval = 85 * 60 * 60
        let provider = RateLimitedDigestLLMProvider(retryAfterSeconds: cooldown)
        let gate = ProviderRequestGate(now: clock.now)
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: directory.appendingPathComponent("ENV.md")
            ),
            batchSize: 1,
            minimumInterval: 6 * 60 * 60,
            requestGate: gate,
            nowProvider: clock.now
        )

        await runtime.record(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "rate-limited",
                committedText: "等待恢复"
            )
        )

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(probe.digestSnapshotDecodeCount, 1)
        let loadedDeadline = await runtime.scheduledDeadlineForTesting()
        let deadline = try XCTUnwrap(loadedDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(clock.now()), cooldown, accuracy: 0.001)

        await runtime.processIfNeeded(now: clock.now())
        let requestsAfterExplicitCheck = await provider.requests
        XCTAssertEqual(requestsAfterExplicitCheck.count, 1)
        XCTAssertEqual(probe.digestSnapshotDecodeCount, 1)
    }

    func testRegistryGenerationChangeWakesLongCooldownWithoutNewInput() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let fingerprintA = String(repeating: "a", count: 64)
        let fingerprintB = String(repeating: "b", count: 64)
        let providerA = NamedLLMProvider(
            name: "digest-provider-a",
            responseText: "## Global Style\n- provider A"
        )
        let providerB = NamedLLMProvider(
            name: "digest-provider-b",
            responseText: "## Global Style\n- provider B"
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: fingerprintA,
            provider: providerA
        )
        let signal = TestProviderRevisionSignal()
        let gate = ProviderRequestGate(now: clock.now)
        let registry = makeRegistry(
            source: source,
            signal: signal,
            requestGate: gate
        )
        let initialLease = await registry.leaseForEligibleDispatch()
        let cooldown: TimeInterval = 85 * 60 * 60
        await gate.recordFailure(
            providerIdentity: fingerprintA,
            generation: initialLease.generation,
            failure: ProviderRateLimitError(
                retryAfterSeconds: cooldown,
                bodyByteCount: 128
            )
        )
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events")
        )
        try await eventStore.append(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "pending-generation-change",
                committedText: "等待新配置"
            )
        )
        let runtime = AIContextMemoryRuntime(
            providerRegistry: registry,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: directory.appendingPathComponent("ENV.md")
            ),
            batchSize: 1,
            minimumInterval: 6 * 60 * 60,
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: clock.now())

        let observedDeadline = await runtime.scheduledDeadlineForTesting()
        let deadline = try XCTUnwrap(observedDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(clock.now()), cooldown, accuracy: 0.001)
        let providerARequestsDuringCooldown = await providerA.requestCount
        let providerBRequestsDuringCooldown = await providerB.requestCount
        XCTAssertEqual(providerARequestsDuringCooldown, 0)
        XCTAssertEqual(providerBRequestsDuringCooldown, 0)

        source.set(
            revision: 2,
            fingerprint: fingerprintB,
            provider: providerB
        )
        signal.send(2)

        try await waitUntil { await providerB.requestCount == 1 }
        try await waitUntil { (try? eventStore.inventory().eventCount) == 0 }
        let providerARequestsAfterChange = await providerA.requestCount
        let providerBRequestsAfterChange = await providerB.requestCount
        XCTAssertEqual(providerARequestsAfterChange, 0)
        XCTAssertEqual(providerBRequestsAfterChange, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
    }

    func testDigestRollingBudgetDoesNotLimitRealtimeRecommendation() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let now = clock.now()
        let sixHours: TimeInterval = 6 * 60 * 60
        let oneDay: TimeInterval = 24 * 60 * 60
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        try await eventStore.append(
            makeContextEvent(rawInput: "digest-pending", committedText: "等待摘要")
        )
        let successfulDigests = [
            now.addingTimeInterval(-18 * 60 * 60),
            now.addingTimeInterval(-12 * 60 * 60),
            now.addingTimeInterval(-6 * 60 * 60),
            now
        ]
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        try environmentStore.saveDigestScheduleState(
            EnvironmentDigestScheduleState(
                pendingSince: now,
                lastSuccessfulDigestAt: now,
                nextEligibleAt: now.addingTimeInterval(sixHours),
                pendingEventCount: 1,
                successfulDigestTimestamps: successfulDigests
            )
        )
        let provider = DigestLLMProvider(generatedMarkdown: "recommended continuation")
        let gate = ProviderRequestGate(now: clock.now)
        let contextRuntime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: sixHours,
            maximumPendingAge: oneDay,
            digestBudgetWindow: oneDay,
            maximumDigestsPerWindow: 4,
            requestGate: gate,
            nowProvider: clock.now
        )

        await contextRuntime.processIfNeeded(now: now)
        let digestRequests = await provider.requests
        XCTAssertTrue(digestRequests.isEmpty)

        let recommendationRuntime = AIRecommendationRuntime(
            provider: provider,
            environmentStore: environmentStore,
            correctionStore: CorrectionInstructionStore(
                fileURL: directory.appendingPathComponent("CORRECTION.md")
            ),
            debounceMilliseconds: 0,
            requestGate: gate
        )
        _ = await recommendationRuntime.recommendation(
            for: AIRecommendationRequest(rawInput: "abc", compositionID: 220)
        )

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.task, .continuation)
        XCTAssertEqual(try eventStore.inventory().eventCount, 1)
    }

    func testSuccessfulDigestRearmsDeadlineForTailAndDrainsOnePrefixPerInterval() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let eventStore = TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events"))
        let provider = DelayedDigestLLMProvider(
            generatedMarkdown: "## Global Style\n- interval",
            delayNanoseconds: 100_000_000
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 1,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        let firstDigest = Task {
            await runtime.record(makeContextEvent(rawInput: "first", committedText: "第一"))
        }
        var firstRequestSeen = false
        let firstDeadline = Date().addingTimeInterval(2)
        while !firstRequestSeen, Date() < firstDeadline {
            firstRequestSeen = !(await provider.requests).isEmpty
            if !firstRequestSeen { try await Task.sleep(nanoseconds: 20_000_000) }
        }
        XCTAssertTrue(firstRequestSeen)
        for index in 0..<60 {
            try await eventStore.append(
                makeContextEvent(rawInput: "tail-\(index)", committedText: "尾部\(index)")
            )
        }
        await firstDigest.value

        clock.advance(by: 2)
        var secondRequestSeen = false
        let secondDeadline = Date().addingTimeInterval(3)
        while !secondRequestSeen, Date() < secondDeadline {
            secondRequestSeen = (await provider.requests).count >= 2
            if !secondRequestSeen { try await Task.sleep(nanoseconds: 20_000_000) }
        }
        XCTAssertTrue(secondRequestSeen)

        var tailAfterSecond = -1
        let secondCompletionDeadline = Date().addingTimeInterval(3)
        while Date() < secondCompletionDeadline {
            let pending = try await eventStore.pendingEvents()
            tailAfterSecond = pending.count
            if tailAfterSecond == 10 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(tailAfterSecond, 10)
        let requestsAfterSecondDigest = await provider.requests
        XCTAssertEqual(requestsAfterSecondDigest.count, 2)

        clock.advance(by: 2)
        var thirdRequestSeen = false
        let thirdDeadline = Date().addingTimeInterval(3)
        while !thirdRequestSeen, Date() < thirdDeadline {
            thirdRequestSeen = (await provider.requests).count >= 3
            if !thirdRequestSeen { try await Task.sleep(nanoseconds: 20_000_000) }
        }
        XCTAssertTrue(thirdRequestSeen)

        var pendingAfterThird: [AITypingEvent] = []
        let thirdCompletionDeadline = Date().addingTimeInterval(3)
        while Date() < thirdCompletionDeadline {
            pendingAfterThird = try await eventStore.pendingEvents()
            if pendingAfterThird.isEmpty { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(pendingAfterThird.isEmpty)
        try await Task.sleep(nanoseconds: 100_000_000)
        let requestsAfterThirdDigest = await provider.requests
        XCTAssertEqual(requestsAfterThirdDigest.count, 3)
    }

    func testBusyGateWakeDrainsPendingDigestWithoutPolling() async throws {
        let directory = makeTemporaryDirectory()
        let provider = DelayedDigestLLMProvider(
            generatedMarkdown: "## Global Style\n- gate wake",
            delayNanoseconds: 20_000_000
        )
        let gateProbe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(testProbe: gateProbe)
        let blockerProbe = ContextGateProbe()
        let blocker = Task {
            try await gate.execute(providerIdentity: provider.providerName, generation: 0) {
                await blockerProbe.markStarted()
                await blockerProbe.waitForRelease()
            }
        }
        try await waitUntil { await blockerProbe.started }

        let eventStoreProbe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: eventStoreProbe
        )
        let runtimeProbe = AIContextMemoryRuntimeTestProbe(
            pausesAfterGateWaiterInstall: true
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 1,
            diagnosticSink: { _ in },
            requestGate: gate,
            testProbe: runtimeProbe
        )
        let firstRecord = Task {
            await runtime.record(makeContextEvent(rawInput: "queued", committedText: "排队"))
        }
        try await waitUntil { await runtimeProbe.gateWaiterPauseCount == 1 }
        let requestsWhileGateBusy = await provider.requests
        XCTAssertTrue(requestsWhileGateBusy.isEmpty)
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, 1)
        XCTAssertEqual(gateProbe.admittedAttemptCount, 1)

        await runtime.record(makeContextEvent(rawInput: "queued-2", committedText: "继续排队"))
        await runtime.record(makeContextEvent(rawInput: "queued-3", committedText: "仍在排队"))
        await runtime.processIfNeeded()
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, 1)
        XCTAssertEqual(gateProbe.admittedAttemptCount, 1)

        await runtimeProbe.releaseGateWaiterInstall()
        await firstRecord.value
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, 1)
        XCTAssertEqual(gateProbe.admittedAttemptCount, 1)

        await blockerProbe.release()
        try await blocker.value
        try await waitUntil { !(await provider.requests).isEmpty }
        let requestsAfterGateWake = await provider.requests
        XCTAssertEqual(requestsAfterGateWake.count, 1)
        try await waitUntil { eventStoreProbe.digestSnapshotDecodeCount == 2 }
        XCTAssertEqual(gateProbe.admittedAttemptCount, 2)
    }

    func testPersistenceBlockedGateRegistryMissingOrDisabledProviderDoesNotRetainEvent() async throws {
        for runtimeLoaderReturnsNil in [true, false] {
            let providerState = runtimeLoaderReturnsNil ? "missing" : "disabled"
            let directory = makeTemporaryDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let gateStateURL = directory.appendingPathComponent("gate.json")
            try Data("corrupt-gate-state".utf8).write(to: gateStateURL)
            let gateProbe = ProviderRequestGateTestProbe()
            let gate = ProviderRequestGate(
                persistenceURL: gateStateURL,
                testProbe: gateProbe
            )
            let eventsDirectory = directory.appendingPathComponent("events")
            let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
            let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
            let provider = DigestLLMProvider(
                generatedMarkdown: "## Global Style\n- must not run"
            )
            let fingerprint = String(repeating: "a", count: 64)
            let source = ProviderRuntimeTestSource(
                revision: 1,
                fingerprint: fingerprint,
                provider: provider
            )
            if runtimeLoaderReturnsNil {
                source.setRuntimeLoadEnabled(false)
            } else {
                source.setRuntimeOverride(
                    revision: 1,
                    fingerprint: fingerprint,
                    provider: nil
                )
            }
            let runtime = AIContextMemoryRuntime(
                providerRegistry: makeRegistry(source: source, requestGate: gate),
                eventStore: eventStore,
                environmentStore: EnvironmentDocumentStore(
                    fileURL: directory.appendingPathComponent("ENV.md")
                ),
                batchSize: 1,
                minimumInterval: 600,
                testProbe: AIContextMemoryRuntimeTestProbe()
            )

            await runtime.record(
                makeContextEvent(
                    rawInput: "blocked-\(providerState)-provider",
                    committedText: "不得保留"
                )
            )

            let requests = await provider.requests
            XCTAssertTrue(requests.isEmpty, providerState)
            XCTAssertFalse(FileManager.default.fileExists(atPath: eventsDirectory.path), providerState)
            XCTAssertFalse(FileManager.default.fileExists(atPath: pendingURL.path), providerState)
            XCTAssertEqual(source.revisionReadCount, 1, providerState)
            XCTAssertEqual(source.runtimeLoadCount, 1, providerState)
            XCTAssertEqual(gateProbe.admittedAttemptCount, 0, providerState)
        }
    }

    func testPersistenceBlockedGateRegistryUsableProviderAppendsWithoutRequest() async throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let gateStateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt-gate-state".utf8).write(to: gateStateURL)
        let gateProbe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            persistenceURL: gateStateURL,
            testProbe: gateProbe
        )
        let eventsDirectory = directory.appendingPathComponent("events")
        let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "b", count: 64),
            provider: provider
        )
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source, requestGate: gate),
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: directory.appendingPathComponent("ENV.md")
            ),
            batchSize: 1,
            minimumInterval: 600,
            testProbe: AIContextMemoryRuntimeTestProbe()
        )

        await runtime.record(
            makeContextEvent(
                rawInput: "blocked-usable-provider",
                committedText: "保留但不请求"
            )
        )

        let requests = await provider.requests
        let pendingEvents = try await eventStore.pendingEvents()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pendingURL.path))
        XCTAssertEqual(pendingEvents.map(\.rawInput), ["blocked-usable-provider"])
        XCTAssertEqual(source.revisionReadCount, 1)
        XCTAssertEqual(source.runtimeLoadCount, 1)
        XCTAssertEqual(gateProbe.admittedAttemptCount, 0)
    }

    func testPersistenceBlockedGateFallbackLeasePreservesAutomaticClaimRecoveryRetry() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let eventsDirectory = directory.appendingPathComponent("events")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        try await eventStore.append(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "persisted-claim-prefix",
                committedText: "已持久化前缀"
            )
        )
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md")
        )
        let generated = "## Global Style\n- recovered automatically"
        _ = try environmentStore.replaceGeneratedSection(with: generated)
        try environmentStore.saveDigestClaim(
            EnvironmentDigestClaim(
                claimedPrefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
                claimedPrefixByteCount: claimedSnapshot.rawData.count,
                claimedEventCount: claimedSnapshot.claimedEventCount,
                generatedSHA256: AIDocumentSnapshot.hash(generated),
                providerGeneration: 0
            )
        )

        let gateStateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt-gate-state".utf8).write(to: gateStateURL)
        let gateProbe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: gateStateURL,
            testProbe: gateProbe
        )
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "c", count: 64),
            provider: provider
        )
        let runtimeProbe = AIContextMemoryRuntimeTestProbe()
        let sleeper = ControlledContextDeadlineSleeper()
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source, requestGate: gate),
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            nowProvider: clock.now,
            testProbe: runtimeProbe,
            claimRecoverySleeper: { nanoseconds in
                await sleeper.suspend(nanoseconds: nanoseconds)
            }
        )

        await runtime.record(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "fallback-tail",
                committedText: "阻断期间追加"
            )
        )

        try await waitUntil { await sleeper.suspensionCount == 1 }
        let blockedRequests = await provider.requests
        XCTAssertNotNil(try environmentStore.loadDigestClaim())
        XCTAssertEqual(try eventStore.inventory().eventCount, 2)
        XCTAssertTrue(blockedRequests.isEmpty)
        XCTAssertEqual(source.revisionReadCount, 1)
        XCTAssertEqual(source.runtimeLoadCount, 1)
        XCTAssertEqual(gateProbe.admittedAttemptCount, 0)

        try Data(#"{"entries":[]}"#.utf8).write(to: gateStateURL, options: .atomic)
        clock.advance(by: 5)
        await sleeper.releaseNext()

        try await waitUntil { (try? environmentStore.loadDigestClaim()) == nil }
        let pendingEvents = try await eventStore.pendingEvents()
        let recoveredRequests = await provider.requests
        let claimRecoveryClaimLoadCount = await runtimeProbe.claimRecoveryClaimLoadCount
        XCTAssertEqual(pendingEvents.map(\.rawInput), ["fallback-tail"])
        XCTAssertTrue(recoveredRequests.isEmpty)
        XCTAssertEqual(gateProbe.persistenceRecoveryProbeCount, 1)
        XCTAssertEqual(gateProbe.persistenceRecoveryCount, 1)
        XCTAssertEqual(claimRecoveryClaimLoadCount, 1)
        XCTAssertEqual(source.revisionReadCount, 1)
        XCTAssertEqual(source.runtimeLoadCount, 1)
    }

    func testFallbackLeaseAwaitPreservesNewClaimRecoveryBackoffAndSkipsAppend() async throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let clock = ManualContextClock()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events")
        )
        try await eventStore.append(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "claim-prefix",
                committedText: "待恢复前缀"
            )
        )
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md")
        )
        let recoveredGenerated = "## Global Style\n- repaired after backoff"
        try environmentStore.saveDigestClaim(
            EnvironmentDigestClaim(
                claimedPrefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
                claimedPrefixByteCount: claimedSnapshot.rawData.count,
                claimedEventCount: claimedSnapshot.claimedEventCount,
                generatedSHA256: AIDocumentSnapshot.hash(recoveredGenerated),
                providerGeneration: 0
            )
        )

        let gateStateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt-gate-state".utf8).write(to: gateStateURL)
        let gateProbe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: gateStateURL,
            testProbe: gateProbe
        )
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "d", count: 64),
            provider: provider
        )
        let leasePause = ContextGateProbe()
        let sleeper = ControlledContextDeadlineSleeper()
        let runtimeProbe = AIContextMemoryRuntimeTestProbe()
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(
                source: source,
                capabilityReset: {
                    await leasePause.markStarted()
                    await leasePause.waitForRelease()
                },
                requestGate: gate
            ),
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 2,
            minimumInterval: 600,
            nowProvider: clock.now,
            testProbe: runtimeProbe,
            claimRecoverySleeper: { nanoseconds in
                await sleeper.suspend(nanoseconds: nanoseconds)
            }
        )
        let record = Task {
            await runtime.record(
                makeContextEvent(
                    timestamp: clock.now(),
                    rawInput: "must-not-append",
                    committedText: "不得追加"
                )
            )
        }

        do {
            try await waitUntil { await leasePause.started }
            try await waitUntil { await sleeper.suspensionCount == 1 }
            try Data(#"{"entries":[]}"#.utf8).write(to: gateStateURL, options: .atomic)
            clock.advance(by: 5)
            await sleeper.releaseNext()
            try await waitUntil { await runtimeProbe.claimRecoveryRetryScheduleCount == 1 }
            try await waitUntil { await sleeper.suspensionCount == 2 }
        } catch {
            await leasePause.release()
            await record.value
            throw error
        }

        await leasePause.release()
        await record.value

        let blockedPendingEvents = try await eventStore.pendingEvents()
        let blockedRequests = await provider.requests
        XCTAssertEqual(blockedPendingEvents.map(\.rawInput), ["claim-prefix"])
        XCTAssertTrue(blockedRequests.isEmpty)
        XCTAssertNotNil(try environmentStore.loadDigestClaim())
        XCTAssertEqual(source.revisionReadCount, 1)
        XCTAssertEqual(source.runtimeLoadCount, 1)

        _ = try environmentStore.replaceGeneratedSection(with: recoveredGenerated)
        clock.advance(by: 60)
        await sleeper.releaseNext()

        try await waitUntil { (try? environmentStore.loadDigestClaim()) == nil }
        let recoveredPendingEvents = try await eventStore.pendingEvents()
        let recoveredRequests = await provider.requests
        XCTAssertTrue(recoveredPendingEvents.isEmpty)
        XCTAssertTrue(recoveredRequests.isEmpty)
        XCTAssertEqual(gateProbe.persistenceRecoveryCount, 1)
    }

    func testFallbackLeaseAwaitRecoveryTransitionsRecordToNormalScheduling() async throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let clock = ManualContextClock()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events")
        )
        try await eventStore.append(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "claim-prefix",
                committedText: "待恢复前缀"
            )
        )
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md")
        )
        let recoveredGenerated = "## Global Style\n- recovered during lease"
        _ = try environmentStore.replaceGeneratedSection(with: recoveredGenerated)
        try environmentStore.saveDigestClaim(
            EnvironmentDigestClaim(
                claimedPrefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
                claimedPrefixByteCount: claimedSnapshot.rawData.count,
                claimedEventCount: claimedSnapshot.claimedEventCount,
                generatedSHA256: AIDocumentSnapshot.hash(recoveredGenerated),
                providerGeneration: 0
            )
        )

        let gateStateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt-gate-state".utf8).write(to: gateStateURL)
        let gateProbe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: gateStateURL,
            testProbe: gateProbe
        )
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "e", count: 64),
            provider: provider
        )
        let leasePause = ContextGateProbe()
        let sleeper = ControlledContextDeadlineSleeper()
        let runtimeProbe = AIContextMemoryRuntimeTestProbe()
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(
                source: source,
                capabilityReset: {
                    await leasePause.markStarted()
                    await leasePause.waitForRelease()
                },
                requestGate: gate
            ),
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 2,
            minimumInterval: 600,
            nowProvider: clock.now,
            testProbe: runtimeProbe,
            claimRecoverySleeper: { nanoseconds in
                await sleeper.suspend(nanoseconds: nanoseconds)
            }
        )
        let record = Task {
            await runtime.record(
                makeContextEvent(
                    timestamp: clock.now(),
                    rawInput: "normal-tail",
                    committedText: "恢复后正常调度"
                )
            )
        }

        do {
            try await waitUntil { await leasePause.started }
            try await waitUntil { await sleeper.suspensionCount == 1 }
            try Data(#"{"entries":[]}"#.utf8).write(to: gateStateURL, options: .atomic)
            clock.advance(by: 5)
            await sleeper.releaseNext()
            try await waitUntil { (try? environmentStore.loadDigestClaim()) == nil }
            try await waitUntil { (try? eventStore.inventory().eventCount) == 0 }
        } catch {
            await leasePause.release()
            await record.value
            throw error
        }

        let deadlineBeforeLeaseReturns = await runtime.scheduledDeadlineForTesting()
        XCTAssertNil(deadlineBeforeLeaseReturns)
        await leasePause.release()
        await record.value

        let pendingEvents = try await eventStore.pendingEvents()
        let requests = await provider.requests
        let scheduledDeadline = await runtime.scheduledDeadlineForTesting()
        XCTAssertEqual(pendingEvents.map(\.rawInput), ["normal-tail"])
        XCTAssertTrue(requests.isEmpty)
        XCTAssertGreaterThan(try XCTUnwrap(scheduledDeadline), clock.now())
        XCTAssertEqual(gateProbe.persistenceRecoveryProbeCount, 1)
        XCTAssertEqual(gateProbe.persistenceRecoveryCount, 1)
        XCTAssertEqual(source.revisionReadCount, 1)
        XCTAssertEqual(source.runtimeLoadCount, 1)
    }

    func testPersistenceBlockedGateDefersClaimRecoveryWithoutRepeatedSensitiveReads() async throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let gateStateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt-gate-state".utf8).write(to: gateStateURL)
        let clock = ManualContextClock()
        let gateProbe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: gateStateURL,
            testProbe: gateProbe
        )
        let eventStoreProbe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: eventStoreProbe
        )
        try await eventStore.append(
            makeContextEvent(
                rawInput: "blocked-digest-private-input",
                committedText: "阻断内容"
            )
        )
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let environmentStore = EnvironmentDocumentStore(
            fileURL: environmentURL,
            testProbe: environmentProbe
        )
        _ = try environmentStore.loadSnapshot()
        let recoveredGenerated = "## Global Style\n- recovered claim"
        try environmentStore.saveDigestClaim(
            EnvironmentDigestClaim(
                claimedPrefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
                claimedPrefixByteCount: claimedSnapshot.rawData.count,
                claimedEventCount: claimedSnapshot.claimedEventCount,
                generatedSHA256: AIDocumentSnapshot.hash(recoveredGenerated),
                providerGeneration: 0
            )
        )
        let digestDecodesBeforeRuntime = eventStoreProbe.digestSnapshotDecodeCount
        let environmentReadsBeforeRuntime = environmentProbe.environmentDocumentReadCount
        let diagnostics = ContextMemoryDiagnosticProbe()
        let runtimeProbe = AIContextMemoryRuntimeTestProbe()
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            diagnosticSink: { diagnostics.record($0) },
            requestGate: gate,
            nowProvider: clock.now,
            testProbe: runtimeProbe
        )

        for _ in 0..<10 {
            await runtime.processIfNeeded(now: clock.now())
        }

        let blockedProviderRequests = await provider.requests
        XCTAssertTrue(blockedProviderRequests.isEmpty)
        XCTAssertEqual(gateProbe.preflightCheckCount, 10)
        XCTAssertEqual(gateProbe.admittedAttemptCount, 0)
        XCTAssertEqual(gateProbe.persistenceRecoveryProbeCount, 0)
        let blockedClaimLoadCount = await runtimeProbe.claimRecoveryClaimLoadCount
        XCTAssertEqual(blockedClaimLoadCount, 0)
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, digestDecodesBeforeRuntime)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, environmentReadsBeforeRuntime)
        XCTAssertEqual(diagnostics.stageCount("context_gate_persistence_blocked"), 1)
        XCTAssertFalse(diagnostics.lines.joined().contains("blocked-digest-private-input"))
        XCTAssertFalse(diagnostics.lines.joined().contains("阻断内容"))

        _ = try environmentStore.replaceGeneratedSection(with: recoveredGenerated)
        try Data(#"{"entries":[]}"#.utf8).write(to: gateStateURL, options: .atomic)
        clock.advance(by: 5)
        await runtime.processIfNeeded(now: clock.now())

        let recoveredClaimLoadCount = await runtimeProbe.claimRecoveryClaimLoadCount
        XCTAssertEqual(recoveredClaimLoadCount, 1)
        XCTAssertNil(try environmentStore.loadDigestClaim())
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
        let requestsAfterClaimRecovery = await provider.requests
        XCTAssertTrue(requestsAfterClaimRecovery.isEmpty)

        await runtime.record(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "post-recovery",
                committedText: "恢复后事件"
            )
        )
        XCTAssertEqual(try eventStore.inventory().eventCount, 1)
    }

    func testPersistenceBlockedGateCompactionPreservesPersistedClaimPrefix() async throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let clock = ManualContextClock()
        let eventsDirectory = directory.appendingPathComponent("events")
        let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        let eventStoreProbe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: .default,
            testProbe: eventStoreProbe
        )
        for index in 0..<500 {
            _ = try eventStore.appendBounded(
                makeContextEvent(
                    timestamp: clock.now().addingTimeInterval(Double(index) / 1_000),
                    rawInput: "claim-backlog-\(index)",
                    committedText: "待恢复-\(index)"
                )
            )
        }
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        XCTAssertEqual(claimedSnapshot.claimedEventCount, 50)

        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md"),
            testProbe: environmentProbe
        )
        let generated = "## Global Style\n- persisted before gate failure"
        _ = try environmentStore.replaceGeneratedSection(with: generated)
        let claim = EnvironmentDigestClaim(
            claimedPrefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
            claimedPrefixByteCount: claimedSnapshot.rawData.count,
            claimedEventCount: claimedSnapshot.claimedEventCount,
            generatedSHA256: AIDocumentSnapshot.hash(generated),
            providerGeneration: 0
        )
        try environmentStore.saveDigestClaim(claim)

        let gateStateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt-gate-state".utf8).write(to: gateStateURL)
        let gateProbe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: gateStateURL,
            testProbe: gateProbe
        )
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "a", count: 64),
            provider: provider
        )
        let runtimeProbe = AIContextMemoryRuntimeTestProbe()
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source, requestGate: gate),
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            nowProvider: clock.now,
            testProbe: runtimeProbe
        )
        let digestDecodesBeforeRecord = eventStoreProbe.digestSnapshotDecodeCount
        let environmentReadsBeforeRecord = environmentProbe.environmentDocumentReadCount

        await runtime.record(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "claim-backlog-newest",
                committedText: "阻断期间最新事件"
            )
        )

        let blockedProviderRequests = await provider.requests
        let blockedClaimLoadCount = await runtimeProbe.claimRecoveryClaimLoadCount
        let compactedInventory = try eventStore.inventory()
        let compactedData = try Data(contentsOf: pendingURL)
        let retainedClaimPrefix = Data(
            compactedData.prefix(claim.claimedPrefixByteCount)
        )
        XCTAssertTrue(blockedProviderRequests.isEmpty)
        XCTAssertEqual(blockedClaimLoadCount, 0)
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, digestDecodesBeforeRecord)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, environmentReadsBeforeRecord)
        XCTAssertEqual(source.revisionReadCount, 1)
        XCTAssertEqual(source.runtimeLoadCount, 1)
        XCTAssertEqual(gateProbe.admittedAttemptCount, 0)
        XCTAssertEqual(eventStoreProbe.atomicRewriteCount, 1)
        XCTAssertEqual(compactedInventory.eventCount, 450)
        XCTAssertLessThanOrEqual(compactedInventory.eventCount, 500)
        XCTAssertLessThanOrEqual(compactedInventory.byteCount, 786_432)
        XCTAssertLessThanOrEqual(compactedInventory.byteCount, 1_048_576)
        XCTAssertEqual(retainedClaimPrefix, claimedSnapshot.rawData)
        XCTAssertEqual(
            AIDocumentSnapshot.hash(String(decoding: retainedClaimPrefix, as: UTF8.self)),
            claim.claimedPrefixSHA256
        )
        let compactedEvents = try await eventStore.pendingEvents()
        XCTAssertEqual(
            compactedEvents.prefix(50).map(\.rawInput),
            (0..<50).map { Optional("claim-backlog-\($0)") }
        )
        XCTAssertEqual(compactedEvents.last?.rawInput, "claim-backlog-newest")

        try Data(#"{"entries":[]}"#.utf8).write(to: gateStateURL, options: .atomic)
        clock.advance(by: 5)
        await runtime.processIfNeeded(now: clock.now())

        let recoveredClaimLoadCount = await runtimeProbe.claimRecoveryClaimLoadCount
        let requestsAfterRecovery = await provider.requests
        let pendingAfterRecovery = try await eventStore.pendingEvents()
        XCTAssertEqual(recoveredClaimLoadCount, 1)
        XCTAssertNil(try environmentStore.loadDigestClaim())
        XCTAssertEqual(
            eventStore.processedArchiveValidation(
                prefixSHA256: claim.claimedPrefixSHA256,
                byteCount: claim.claimedPrefixByteCount
            ),
            .valid
        )
        XCTAssertTrue(requestsAfterRecovery.isEmpty)
        XCTAssertEqual(
            eventStoreProbe.digestSnapshotDecodeCount,
            digestDecodesBeforeRecord + 1
        )
        XCTAssertEqual(source.revisionReadCount, 1)
        XCTAssertEqual(source.runtimeLoadCount, 1)
        XCTAssertEqual(pendingAfterRecovery.count, 400)
        XCTAssertEqual(pendingAfterRecovery.first?.rawInput, "claim-backlog-101")
        XCTAssertEqual(pendingAfterRecovery.last?.rawInput, "claim-backlog-newest")
    }

    func testPotentialDigestAppendSeparatesExistingLegacyEOFRecord() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let existingEvent = makeContextEvent(
            rawInput: "legacy-eof-existing",
            committedText: "已有事件"
        )
        let appendedEvent = makeContextEvent(
            rawInput: "legacy-eof-appended",
            committedText: "追加事件"
        )
        let existingData = try encoder.encode(existingEvent)
        try existingData.write(to: pendingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: .default,
            testProbe: probe
        )

        let result = try eventStore.appendBounded(
            appendedEvent,
            prefixProtection: .potentialDigest
        )

        let pendingData = try Data(contentsOf: pendingURL)
        let inventory = try eventStore.inventory()
        let events = try await eventStore.pendingEvents()
        let appendedLineData = Data(pendingData.dropFirst(existingData.count + 1))
        let appendedRecordData = Data(appendedLineData.dropLast())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedAppendedEvent = try decoder.decode(
            AITypingEvent.self,
            from: appendedRecordData
        )
        XCTAssertEqual(Data(pendingData.prefix(existingData.count)), existingData)
        XCTAssertEqual(pendingData.dropFirst(existingData.count).first, 0x0A)
        XCTAssertNotEqual(pendingData.dropFirst(existingData.count + 1).first, 0x0A)
        XCTAssertEqual(pendingData.filter { $0 == 0x0A }.count, 2)
        XCTAssertEqual(appendedLineData.last, 0x0A)
        XCTAssertEqual(decodedAppendedEvent.rawInput, appendedEvent.rawInput)
        XCTAssertEqual(decodedAppendedEvent.committedText, appendedEvent.committedText)
        XCTAssertEqual(result.inventory.eventCount, 2)
        XCTAssertEqual(result.inventory.byteCount, pendingData.count)
        XCTAssertEqual(inventory.eventCount, 2)
        XCTAssertEqual(inventory.byteCount, pendingData.count)
        XCTAssertEqual(events.map(\.rawInput), ["legacy-eof-existing", "legacy-eof-appended"])
        XCTAssertEqual(result.droppedByteCount, 0)
        XCTAssertEqual(probe.atomicRewriteCount, 0)
    }

    func testPersistenceBlockedGateCompactionPreservesLegacyEOFClaimAtDigestByteLimit() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let eventsDirectory = directory.appendingPathComponent("events")
        let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        var policy = TypingEventRetentionPolicy.default
        policy.maximumPendingEventCount = 5
        policy.compactedPendingEventCount = 4
        policy.maximumDigestEventCount = 2
        policy.maximumDigestByteCount = 512
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let firstLegacyEvent = makeContextEvent(
            timestamp: clock.now(),
            rawInput: "legacy-eof-claim-1",
            committedText: "首条"
        )
        var firstLegacyData = try encoder.encode(firstLegacyEvent)
        firstLegacyData.append(0x0A)
        var trailingLegacyEvent = makeContextEvent(
            timestamp: clock.now(),
            rawInput: "legacy-eof-claim-2",
            committedText: ""
        )
        let unpaddedTrailingData = try encoder.encode(trailingLegacyEvent)
        let targetClaimByteCount = policy.maximumDigestByteCount - 1
        let paddingCount = try XCTUnwrap(
            targetClaimByteCount >= firstLegacyData.count + unpaddedTrailingData.count
                ? targetClaimByteCount
                    - firstLegacyData.count
                    - unpaddedTrailingData.count
                : nil
        )
        trailingLegacyEvent.committedText = String(repeating: "x", count: paddingCount)
        let trailingLegacyData = try encoder.encode(trailingLegacyEvent)
        var legacyClaimData = Data(capacity: targetClaimByteCount)
        legacyClaimData.append(firstLegacyData)
        legacyClaimData.append(trailingLegacyData)
        XCTAssertEqual(legacyClaimData.count, targetClaimByteCount)
        XCTAssertLessThan(legacyClaimData.count, policy.maximumDigestByteCount)
        XCTAssertNotEqual(legacyClaimData.last, 0x0A)
        try legacyClaimData.write(to: pendingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )

        let eventStoreProbe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            testProbe: eventStoreProbe
        )
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        XCTAssertEqual(claimedSnapshot.rawData, legacyClaimData)
        XCTAssertEqual(claimedSnapshot.requestData.count, policy.maximumDigestByteCount)
        XCTAssertEqual(claimedSnapshot.claimedEventCount, 2)
        XCTAssertEqual(
            claimedSnapshot.events.map(\.rawInput),
            ["legacy-eof-claim-1", "legacy-eof-claim-2"]
        )

        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md"),
            testProbe: environmentProbe
        )
        let generated = "## Global Style\n- legacy EOF claim"
        _ = try environmentStore.replaceGeneratedSection(with: generated)
        let claim = EnvironmentDigestClaim(
            claimedPrefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
            claimedPrefixByteCount: claimedSnapshot.rawData.count,
            claimedEventCount: claimedSnapshot.claimedEventCount,
            generatedSHA256: AIDocumentSnapshot.hash(generated),
            providerGeneration: 0
        )
        try environmentStore.saveDigestClaim(claim)

        var firstTailLine = try encoder.encode(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "legacy-tail-0",
                committedText: "尾部-0"
            )
        )
        firstTailLine.append(0x0A)
        var historicalPendingData = legacyClaimData
        historicalPendingData.append(firstTailLine)
        try historicalPendingData.write(to: pendingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )

        let gateStateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt-gate-state".utf8).write(to: gateStateURL)
        let gate = ProviderRequestGate(now: clock.now, persistenceURL: gateStateURL)
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let source = ProviderRuntimeTestSource(
            revision: 1,
            fingerprint: String(repeating: "b", count: 64),
            provider: provider
        )
        let runtimeProbe = AIContextMemoryRuntimeTestProbe()
        let runtime = AIContextMemoryRuntime(
            providerRegistry: makeRegistry(source: source, requestGate: gate),
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            nowProvider: clock.now,
            testProbe: runtimeProbe
        )
        let digestDecodesBeforeRecords = eventStoreProbe.digestSnapshotDecodeCount
        let environmentReadsBeforeRecords = environmentProbe.environmentDocumentReadCount

        let crossingRecordByteCount = policy.maximumDigestByteCount - legacyClaimData.count
        XCTAssertGreaterThan(crossingRecordByteCount, 0)
        XCTAssertGreaterThan(firstTailLine.count, crossingRecordByteCount)
        XCTAssertGreaterThan(historicalPendingData.count, policy.maximumDigestByteCount)
        XCTAssertNotEqual(
            historicalPendingData[
                historicalPendingData.index(
                    historicalPendingData.startIndex,
                    offsetBy: policy.maximumDigestByteCount - 1
                )
            ],
            0x0A
        )
        XCTAssertEqual(firstTailLine.last, 0x0A)

        for index in 1..<5 {
            await runtime.record(
                makeContextEvent(
                    timestamp: clock.now(),
                    rawInput: "legacy-tail-\(index)",
                    committedText: "尾部-\(index)"
                )
            )
        }

        let blockedRequests = await provider.requests
        let blockedClaimLoadCount = await runtimeProbe.claimRecoveryClaimLoadCount
        let compactedData = try Data(contentsOf: pendingURL)
        let compactedTailData = Data(compactedData.dropFirst(legacyClaimData.count))
        let compactedTailEvents = try compactedTailData
            .split(separator: 0x0A)
            .map { try decoder.decode(AITypingEvent.self, from: Data($0)) }
        XCTAssertTrue(blockedRequests.isEmpty)
        XCTAssertEqual(blockedClaimLoadCount, 0)
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, digestDecodesBeforeRecords)
        XCTAssertEqual(
            environmentProbe.environmentDocumentReadCount,
            environmentReadsBeforeRecords
        )
        XCTAssertEqual(source.revisionReadCount, 4)
        XCTAssertEqual(source.runtimeLoadCount, 1)
        XCTAssertEqual(eventStoreProbe.atomicRewriteCount, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 4)
        XCTAssertGreaterThan(compactedData.count, policy.maximumDigestByteCount)
        XCTAssertLessThanOrEqual(compactedData.count, policy.compactedPendingByteCount)
        XCTAssertLessThanOrEqual(compactedData.count, policy.maximumPendingByteCount)
        XCTAssertTrue(compactedData.starts(with: legacyClaimData))
        XCTAssertTrue(compactedTailData.starts(with: firstTailLine))
        XCTAssertEqual(
            rawDataSHA256(Data(compactedData.prefix(legacyClaimData.count))),
            claim.claimedPrefixSHA256
        )
        XCTAssertEqual(
            compactedTailEvents.map(\.rawInput),
            ["legacy-tail-0", "legacy-tail-3", "legacy-tail-4"]
        )

        try Data(#"{"entries":[]}"#.utf8).write(to: gateStateURL, options: .atomic)
        clock.advance(by: 5)
        await runtime.processIfNeeded(now: clock.now())

        let recoveredClaimLoadCount = await runtimeProbe.claimRecoveryClaimLoadCount
        let requestsAfterRecovery = await provider.requests
        let remainingData = try Data(contentsOf: pendingURL)
        let pendingAfterRecovery = try await eventStore.pendingEvents()
        XCTAssertEqual(recoveredClaimLoadCount, 1)
        XCTAssertNil(try environmentStore.loadDigestClaim())
        XCTAssertEqual(
            eventStore.processedArchiveValidation(
                prefixSHA256: claim.claimedPrefixSHA256,
                byteCount: claim.claimedPrefixByteCount
            ),
            .valid
        )
        XCTAssertTrue(requestsAfterRecovery.isEmpty)
        XCTAssertEqual(source.revisionReadCount, 4)
        XCTAssertEqual(source.runtimeLoadCount, 1)
        XCTAssertEqual(
            eventStoreProbe.digestSnapshotDecodeCount,
            digestDecodesBeforeRecords + 1
        )
        XCTAssertTrue(remainingData.starts(with: firstTailLine))
        XCTAssertEqual(
            pendingAfterRecovery.map(\.rawInput),
            ["legacy-tail-0", "legacy-tail-3", "legacy-tail-4"]
        )
    }

    func testClaimedCompactionPreservesLegacyEOFPrefixWithoutNewline() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        var policy = TypingEventRetentionPolicy.default
        policy.maximumPendingEventCount = 4
        policy.compactedPendingEventCount = 3
        policy.maximumDigestEventCount = 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacyEvent = makeContextEvent(
            rawInput: "known-legacy-claim",
            committedText: "已知旧声明"
        )
        let legacyClaimData = try encoder.encode(legacyEvent)
        try legacyClaimData.write(to: pendingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy
        )
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        let legacyClaimSHA256 = rawDataSHA256(legacyClaimData)
        XCTAssertEqual(claimedSnapshot.rawData, legacyClaimData)

        for index in 0..<4 {
            _ = try eventStore.appendBounded(
                makeContextEvent(
                    rawInput: "known-tail-\(index)",
                    committedText: "尾部-\(index)"
                ),
                prefixProtection: .claimed(legacyClaimData)
            )
        }

        let compactedData = try Data(contentsOf: pendingURL)
        let compactedEvents = try await eventStore.pendingEvents()
        XCTAssertEqual(
            Data(compactedData.prefix(legacyClaimData.count)),
            legacyClaimData
        )
        XCTAssertEqual(
            rawDataSHA256(Data(compactedData.prefix(legacyClaimData.count))),
            legacyClaimSHA256
        )
        XCTAssertEqual(compactedData.dropFirst(legacyClaimData.count).first, 0x0A)
        let expectedPendingData = Data(
            compactedData.dropFirst(legacyClaimData.count + 1)
        )
        XCTAssertEqual(
            compactedEvents.map(\.rawInput),
            ["known-legacy-claim", "known-tail-2", "known-tail-3"]
        )

        try eventStore.archivePendingEvents(matching: claimedSnapshot)

        let archiveURL = eventsDirectory
            .appendingPathComponent("processed")
            .appendingPathComponent("typing-events-\(legacyClaimSHA256).jsonl")
        let archivedData = try Data(contentsOf: archiveURL)
        let pendingData = try Data(contentsOf: pendingURL)
        let inventory = try eventStore.inventory()
        let pendingAfterArchive = try await eventStore.pendingEvents()
        XCTAssertEqual(archivedData, legacyClaimData)
        XCTAssertEqual(rawDataSHA256(archivedData), legacyClaimSHA256)
        XCTAssertEqual(pendingData, expectedPendingData)
        XCTAssertEqual(pendingData.first, 0x7B)
        XCTAssertEqual(inventory.byteCount, pendingData.count)
        XCTAssertEqual(inventory.eventCount, 2)
        XCTAssertEqual(
            pendingAfterArchive.map(\.rawInput),
            ["known-tail-2", "known-tail-3"]
        )
    }

    func testPotentialDigestCompactionStopsAtEventCapBeforePartialNextRecord() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let firstEvent = makeContextEvent(
            rawInput: "event-cap-first",
            committedText: "首条"
        )
        let secondEvent = makeContextEvent(
            rawInput: "event-cap-second",
            committedText: String(repeating: "x", count: 512)
        )
        let newestEvent = makeContextEvent(
            rawInput: "event-cap-newest",
            committedText: "最新"
        )
        var firstLine = try encoder.encode(firstEvent)
        firstLine.append(0x0A)
        var secondLine = try encoder.encode(secondEvent)
        secondLine.append(0x0A)
        var newestLine = try encoder.encode(newestEvent)
        newestLine.append(0x0A)
        var policy = TypingEventRetentionPolicy.default
        policy.maximumPendingEventCount = 2
        policy.compactedPendingEventCount = 2
        policy.maximumDigestEventCount = 1
        policy.maximumDigestByteCount = max(firstLine.count + 1, newestLine.count)
        XCTAssertGreaterThan(policy.maximumDigestByteCount, firstLine.count)
        XCTAssertLessThan(policy.maximumDigestByteCount, firstLine.count + secondLine.count)
        var initialData = firstLine
        initialData.append(secondLine)
        try initialData.write(to: pendingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            testProbe: probe
        )

        _ = try eventStore.appendBounded(
            newestEvent,
            prefixProtection: .potentialDigest
        )

        let compactedData = try Data(contentsOf: pendingURL)
        let compactedEvents = try await eventStore.pendingEvents()
        XCTAssertEqual(probe.atomicRewriteCount, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 2)
        XCTAssertLessThanOrEqual(compactedData.count, policy.compactedPendingByteCount)
        XCTAssertTrue(compactedData.starts(with: firstLine))
        XCTAssertFalse(String(decoding: compactedData, as: UTF8.self).contains("event-cap-second"))
        XCTAssertEqual(
            compactedEvents.map(\.rawInput),
            ["event-cap-first", "event-cap-newest"]
        )
    }

    func testPotentialDigestCompactionRollsBackAppendWhenCrossingRecordExceedsTarget() throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var firstClaimLine = try encoder.encode(
            makeContextEvent(rawInput: "rollback-claim-first", committedText: "首条")
        )
        firstClaimLine.append(0x0A)
        let trailingClaimData = try encoder.encode(
            makeContextEvent(rawInput: "rollback-claim-trailing", committedText: "末条")
        )
        var crossingTailLine = try encoder.encode(
            makeContextEvent(
                rawInput: "rollback-crossing-tail",
                committedText: String(repeating: "x", count: 512)
            )
        )
        crossingTailLine.append(0x0A)
        let suffixLine = try encoder.encode(
            makeContextEvent(rawInput: "rollback-suffix", committedText: "后缀")
        )
        let appendedEvent = makeContextEvent(
            rawInput: "rollback-rejected-append",
            committedText: "不得破坏声明"
        )
        var appendedLine = try encoder.encode(appendedEvent)
        appendedLine.append(0x0A)
        var initialData = firstClaimLine
        initialData.append(trailingClaimData)
        initialData.append(crossingTailLine)
        initialData.append(suffixLine)
        try initialData.write(to: pendingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )
        var policy = TypingEventRetentionPolicy.default
        policy.maximumPendingEventCount = 3
        policy.compactedPendingEventCount = 3
        policy.maximumPendingByteCount = initialData.count
        policy.compactedPendingByteCount = firstClaimLine.count + trailingClaimData.count + 8
        policy.maximumDigestEventCount = 2
        policy.maximumDigestByteCount = firstClaimLine.count + trailingClaimData.count + 1
        XCTAssertGreaterThan(
            crossingTailLine.count,
            policy.compactedPendingByteCount - policy.maximumDigestByteCount
        )
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            testProbe: probe
        )

        let result = try eventStore.appendBounded(
            appendedEvent,
            prefixProtection: .potentialDigest
        )

        XCTAssertEqual(result.droppedEventCount, 1)
        XCTAssertEqual(result.droppedByteCount, appendedLine.count + 1)
        XCTAssertEqual(result.inventory.eventCount, 3)
        XCTAssertEqual(result.inventory.byteCount, initialData.count)
        XCTAssertLessThanOrEqual(result.inventory.byteCount, policy.maximumPendingByteCount)
        XCTAssertEqual(probe.atomicRewriteCount, 1)
        XCTAssertEqual(try Data(contentsOf: pendingURL), initialData)
    }

    func testPersistenceBlockedGateRecoversDigestWithoutRuntimeRebuildOrEventLoss() async throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let gateStateURL = directory.appendingPathComponent("gate.json")
        try Data("corrupt-gate-state".utf8).write(to: gateStateURL)
        let clock = ManualContextClock()
        let gateProbe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(
            now: clock.now,
            persistenceURL: gateStateURL,
            testProbe: gateProbe
        )
        let eventStoreProbe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: eventStoreProbe
        )
        try await eventStore.append(
            makeContextEvent(
                rawInput: "recover-digest-private-input",
                committedText: "待恢复内容"
            )
        )
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- Recovered digest."
        )
        let diagnostics = ContextMemoryDiagnosticProbe()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: environmentURL,
                testProbe: environmentProbe
            ),
            batchSize: 1,
            minimumInterval: 600,
            diagnosticSink: { diagnostics.record($0) },
            requestGate: gate,
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: clock.now())
        await runtime.record(
            makeContextEvent(
                rawInput: "recover-digest-tail-private-input",
                committedText: "恢复期间追加"
            )
        )

        let blockedRequests = await provider.requests
        let blockedInventory = try eventStore.inventory()
        XCTAssertTrue(blockedRequests.isEmpty)
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, 0)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, 0)
        XCTAssertEqual(blockedInventory.eventCount, 2)
        XCTAssertEqual(diagnostics.stageCount("context_gate_persistence_blocked"), 1)

        try Data(#"{"entries":[]}"#.utf8).write(to: gateStateURL, options: .atomic)
        clock.advance(by: 5)
        await runtime.processIfNeeded(now: clock.now())

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(gateProbe.admittedAttemptCount, 1)
        XCTAssertEqual(gateProbe.persistenceRecoveryProbeCount, 1)
        XCTAssertEqual(gateProbe.persistenceRecoveryCount, 1)
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, 1)
        XCTAssertGreaterThan(environmentProbe.environmentDocumentReadCount, 0)
        let recoveredInventory = try eventStore.inventory()
        XCTAssertEqual(recoveredInventory.eventCount, 0)
        let environment = try String(contentsOf: environmentURL, encoding: .utf8)
        XCTAssertTrue(environment.contains("Recovered digest."))
        XCTAssertFalse(diagnostics.lines.joined().contains("recover-digest-private-input"))
        XCTAssertFalse(diagnostics.lines.joined().contains("recover-digest-tail-private-input"))
        XCTAssertFalse(diagnostics.lines.joined().contains("待恢复内容"))
        XCTAssertFalse(diagnostics.lines.joined().contains("恢复期间追加"))
    }

    func testProcessedArchivePendingPrefixValidationIsExactAndFailClosed() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        let probe = TypingEventStoreTestProbe()
        let store = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: .default,
            testProbe: probe
        )
        let claimedEvent = makeContextEvent(rawInput: "claimed", committedText: "已声明")
        try await store.append(claimedEvent)
        let snapshot = try store.pendingDigestSnapshot()
        let prefixSHA256 = AIDocumentSnapshot.hash(snapshot.rawContent)
        _ = try store.commitPendingEvents(matching: snapshot, beforeArchive: {})

        XCTAssertEqual(
            store.pendingClaimedPrefixValidation(
                prefixSHA256: prefixSHA256,
                byteCount: snapshot.rawData.count,
                eventCount: snapshot.claimedEventCount
            ),
            .missing
        )

        try await store.append(
            makeContextEvent(
                rawInput: "tail-only-" + String(repeating: "x", count: 512),
                committedText: "尾部"
            )
        )
        XCTAssertEqual(
            store.pendingClaimedPrefixValidation(
                prefixSHA256: prefixSHA256,
                byteCount: snapshot.rawData.count,
                eventCount: snapshot.claimedEventCount
            ),
            .notMatching
        )

        try snapshot.rawData.write(to: pendingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )
        switch store.pendingClaimedPrefixValidation(
            prefixSHA256: prefixSHA256,
            byteCount: snapshot.rawData.count,
            eventCount: snapshot.claimedEventCount
        ) {
        case .matching(let recovered):
            XCTAssertEqual(recovered.rawData, snapshot.rawData)
        default:
            XCTFail("expected exact claimed prefix")
        }

        try Data(snapshot.rawData.prefix(max(1, snapshot.rawData.count / 2))).write(
            to: pendingURL,
            options: .atomic
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )
        XCTAssertEqual(
            store.pendingClaimedPrefixValidation(
                prefixSHA256: prefixSHA256,
                byteCount: snapshot.rawData.count,
                eventCount: snapshot.claimedEventCount
            ),
            .indeterminate
        )

        try snapshot.rawData.write(to: pendingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )
        probe.failNextClaimedPrefixReads(1)
        XCTAssertEqual(
            store.pendingClaimedPrefixValidation(
                prefixSHA256: prefixSHA256,
                byteCount: snapshot.rawData.count,
                eventCount: snapshot.claimedEventCount
            ),
            .indeterminate
        )

        let validationForPendingAttributesError: (NSError) -> PendingClaimedPrefixValidation = { error in
            TypingEventStore(
                eventsDirectoryURL: eventsDirectory,
                fileManager: PendingAttributesErrorFileManager(
                    pendingURL: pendingURL,
                    error: error
                ),
                retentionPolicy: .default
            ).pendingClaimedPrefixValidation(
                prefixSHA256: prefixSHA256,
                byteCount: snapshot.rawData.count,
                eventCount: snapshot.claimedEventCount
            )
        }
        let nestedMissingError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [
                NSUnderlyingErrorKey: NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(ENOENT)
                )
            ]
        )
        XCTAssertEqual(
            validationForPendingAttributesError(nestedMissingError),
            .missing
        )

        let nestedNonMissingErrors = [
            NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadNoPermissionError,
                userInfo: [
                    NSUnderlyingErrorKey: NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(EACCES)
                    )
                ]
            ),
            NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadUnknownError,
                userInfo: [
                    NSUnderlyingErrorKey: NSError(
                        domain: "com.knowtype.tests.unknown-io",
                        code: 1
                    )
                ]
            )
        ]
        for error in nestedNonMissingErrors {
            XCTAssertEqual(
                validationForPendingAttributesError(error),
                .indeterminate
            )
        }
    }

    func testProcessedArchiveRecoveryRetainsClaimWhenPendingPrefixReadFails() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let pendingURL = eventsDirectory.appendingPathComponent("typing-events.jsonl")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let probe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: .default,
            testProbe: probe
        )
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        let generated = "## Global Style\n- committed"
        try await eventStore.append(
            makeContextEvent(rawInput: "claimed", committedText: "已声明")
        )
        let snapshot = try eventStore.pendingDigestSnapshot()
        let claim = EnvironmentDigestClaim(
            claimedPrefixSHA256: AIDocumentSnapshot.hash(snapshot.rawContent),
            claimedPrefixByteCount: snapshot.rawData.count,
            claimedEventCount: snapshot.claimedEventCount,
            generatedSHA256: AIDocumentSnapshot.hash(generated),
            providerGeneration: 0
        )
        _ = try environmentStore.replaceGeneratedSection(with: generated)
        try environmentStore.saveDigestClaim(claim)
        _ = try eventStore.commitPendingEvents(matching: snapshot, beforeArchive: {})
        try snapshot.rawData.write(to: pendingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )
        probe.failNextClaimedPrefixReads(1)
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )

        await runtime.processIfNeeded()

        let providerRequests = await provider.requests
        XCTAssertTrue(providerRequests.isEmpty)
        XCTAssertEqual(try environmentStore.loadDigestClaim(), claim)
        XCTAssertEqual(try Data(contentsOf: pendingURL), snapshot.rawData)
        XCTAssertNil(try environmentStore.loadDigestScheduleState())
    }

    func testClaimCleanupFailureWithTailRecoversAfterRestartWithoutProviderRetry() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let successfulDigestAt = clock.now()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: environmentURL,
            testProbe: environmentProbe
        )
        let provider = SuspendedDigestLLMProvider()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        let firstDigest = Task {
            await runtime.record(
                makeContextEvent(
                    timestamp: successfulDigestAt,
                    rawInput: "claimed",
                    committedText: "已声明"
                )
            )
        }
        try await waitUntilProviderReceivesRequest(provider)
        try await eventStore.append(
            makeContextEvent(
                timestamp: successfulDigestAt,
                rawInput: "tail",
                committedText: "尾部"
            )
        )
        environmentProbe.failNextClaimClears(1)
        await provider.finish(generatedMarkdown: "## Global Style\n- recovered")
        await firstDigest.value

        let requestsAfterCleanupFailure = await provider.requests
        XCTAssertEqual(requestsAfterCleanupFailure.count, 1)
        let pendingAfterFailure = try await eventStore.pendingEvents()
        XCTAssertEqual(pendingAfterFailure.map(\.rawInput), ["tail"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("ENV.digest-claim.json").path
            )
        )
        let scheduleBeforeRecovery = try XCTUnwrap(
            environmentStore.loadDigestScheduleState()
        )
        XCTAssertEqual(scheduleBeforeRecovery.successfulDigestTimestamps, [successfulDigestAt])
        let receiptBeforeRecovery = try XCTUnwrap(
            environmentStore.loadDigestArchiveReceipt()
        )
        XCTAssertEqual(receiptBeforeRecovery.successfulDigestAt, successfulDigestAt)

        clock.advance(by: 120)

        let recoveryProvider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- should not run")
        let restartedRuntime = AIContextMemoryRuntime(
            provider: recoveryProvider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )
        await restartedRuntime.processIfNeeded(now: clock.now())

        let recoveryRequests = await recoveryProvider.requests
        XCTAssertTrue(recoveryRequests.isEmpty)
        let pendingAfterRecovery = try await eventStore.pendingEvents()
        XCTAssertEqual(pendingAfterRecovery.map(\.rawInput), ["tail"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ENV.digest-claim.json").path))
        let scheduleAfterRecovery = try XCTUnwrap(
            EnvironmentDocumentStore(fileURL: environmentURL).loadDigestScheduleState()
        )
        XCTAssertEqual(scheduleAfterRecovery.successfulDigestTimestamps, [successfulDigestAt])
        XCTAssertEqual(scheduleAfterRecovery.lastSuccessfulDigestAt, successfulDigestAt)
    }

    func testClaimRecoveryAcceptsBoundedFutureReceiptAfterClockRollback() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let successfulDigestAt = clock.now()
        let fixture = try await makeArchivedDigestClaimRecoveryFixture(
            directory: directory,
            timestamp: successfulDigestAt,
            generated: "## Global Style\n- future receipt"
        )
        let nonFiniteReceipt = digestArchiveReceipt(
            for: fixture.claim,
            successfulDigestAt: Date(timeIntervalSince1970: .infinity)
        )
        XCTAssertThrowsError(
            try fixture.environmentStore.saveDigestArchiveReceipt(nonFiniteReceipt)
        )
        try fixture.environmentStore.saveDigestArchiveReceipt(
            digestArchiveReceipt(
                for: fixture.claim,
                successfulDigestAt: successfulDigestAt
            )
        )

        clock.advance(by: -(2 * 60 * 60))
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: fixture.eventStore,
            environmentStore: fixture.environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: clock.now())

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(try fixture.environmentStore.loadDigestClaim())
        let schedule = try XCTUnwrap(
            fixture.environmentStore.loadDigestScheduleState()
        )
        XCTAssertEqual(schedule.successfulDigestTimestamps, [successfulDigestAt])
        XCTAssertEqual(schedule.lastSuccessfulDigestAt, successfulDigestAt)
    }

    func testClaimRecoveryRejectsReceiptBeyondScheduleAnchorBound() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let fixture = try await makeArchivedDigestClaimRecoveryFixture(
            directory: directory,
            timestamp: clock.now(),
            generated: "## Global Style\n- reject future receipt"
        )
        try fixture.environmentStore.saveDigestArchiveReceipt(
            digestArchiveReceipt(
                for: fixture.claim,
                successfulDigestAt: clock.now().addingTimeInterval(24 * 60 * 60 + 1)
            )
        )
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: fixture.eventStore,
            environmentStore: fixture.environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: clock.now())

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(try fixture.environmentStore.loadDigestClaim(), fixture.claim)
        XCTAssertNil(try fixture.environmentStore.loadDigestScheduleState())
    }

    func testRecordFirstLegacyClaimRecoveryPreservesRollingHistoryBeforeAppending() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let recoveryNow = clock.now()
        let sixHours: TimeInterval = 6 * 60 * 60
        let oneDay: TimeInterval = 24 * 60 * 60
        let priorSuccesses = [
            recoveryNow.addingTimeInterval(-18 * 60 * 60),
            recoveryNow.addingTimeInterval(-12 * 60 * 60),
            recoveryNow.addingTimeInterval(-6 * 60 * 60)
        ]
        let fixture = try await makeArchivedDigestClaimRecoveryFixture(
            directory: directory,
            timestamp: recoveryNow,
            generated: "## Global Style\n- record-first recovery"
        )
        try writeLegacyDigestArchiveReceipt(for: fixture.claim, in: directory)
        try fixture.environmentStore.saveDigestScheduleState(
            EnvironmentDigestScheduleState(
                pendingSince: nil,
                lastSuccessfulDigestAt: priorSuccesses.last,
                nextEligibleAt: nil,
                pendingEventCount: 0,
                successfulDigestTimestamps: priorSuccesses
            )
        )
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: fixture.eventStore,
            environmentStore: fixture.environmentStore,
            batchSize: 1,
            minimumInterval: sixHours,
            maximumPendingAge: oneDay,
            digestBudgetWindow: oneDay,
            maximumDigestsPerWindow: 4,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.record(
            makeContextEvent(
                timestamp: recoveryNow,
                rawInput: "record-after-recovery",
                committedText: "恢复后记录"
            )
        )

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(try fixture.environmentStore.loadDigestClaim())
        XCTAssertNil(try fixture.environmentStore.loadDigestArchiveReceipt())
        let pending = try fixture.eventStore.pendingDigestSnapshot()
        XCTAssertEqual(
            pending.events.compactMap(\.rawInput),
            ["record-after-recovery"]
        )
        let schedule = try XCTUnwrap(
            fixture.environmentStore.loadDigestScheduleState()
        )
        XCTAssertEqual(
            schedule.successfulDigestTimestamps,
            priorSuccesses + [recoveryNow]
        )
        XCTAssertEqual(schedule.lastSuccessfulDigestAt, recoveryNow)
        XCTAssertEqual(schedule.pendingEventCount, 1)
        XCTAssertEqual(
            schedule.nextEligibleAt,
            recoveryNow.addingTimeInterval(sixHours)
        )
        let scheduledDeadline = await runtime.scheduledDeadlineForTesting()
        XCTAssertEqual(
            scheduledDeadline,
            recoveryNow.addingTimeInterval(sixHours)
        )
    }

    func testLegacyClaimRecoveryPreservesBoundedFutureScheduleAcrossRestart() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let futureSuccess = clock.now()
        let sixHours: TimeInterval = 6 * 60 * 60
        let oneDay: TimeInterval = 24 * 60 * 60
        let fixture = try await makeArchivedDigestClaimRecoveryFixture(
            directory: directory,
            timestamp: futureSuccess,
            generated: "## Global Style\n- future legacy recovery"
        )
        try writeLegacyDigestArchiveReceipt(for: fixture.claim, in: directory)
        try writeLegacyDigestSchedule(
            lastSuccessfulDigestAt: futureSuccess,
            pendingEventCount: 0,
            in: directory
        )

        clock.advance(by: -(2 * 60 * 60))
        let recoveryNow = clock.now()
        try await fixture.eventStore.append(
            makeContextEvent(
                timestamp: recoveryNow,
                rawInput: "pending-after-rollback",
                committedText: "回拨后待处理"
            )
        )
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: fixture.eventStore,
            environmentStore: fixture.environmentStore,
            batchSize: 1,
            minimumInterval: sixHours,
            maximumPendingAge: oneDay,
            digestBudgetWindow: oneDay,
            maximumDigestsPerWindow: 4,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: recoveryNow)

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(try fixture.environmentStore.loadDigestClaim())
        let expectedDeadline = futureSuccess.addingTimeInterval(sixHours)
        let recoveredSchedule = try XCTUnwrap(
            fixture.environmentStore.loadDigestScheduleState()
        )
        XCTAssertEqual(
            recoveredSchedule.successfulDigestTimestamps,
            [recoveryNow, futureSuccess]
        )
        XCTAssertEqual(recoveredSchedule.lastSuccessfulDigestAt, futureSuccess)
        XCTAssertEqual(recoveredSchedule.nextEligibleAt, expectedDeadline)
        XCTAssertEqual(recoveredSchedule.pendingEventCount, 1)

        let restartedProvider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must still not run"
        )
        let restartedStore = EnvironmentDocumentStore(
            fileURL: fixture.environmentURL
        )
        let restartedRuntime = AIContextMemoryRuntime(
            provider: restartedProvider,
            eventStore: TypingEventStore(
                eventsDirectoryURL: directory.appendingPathComponent("events")
            ),
            environmentStore: restartedStore,
            batchSize: 1,
            minimumInterval: sixHours,
            maximumPendingAge: oneDay,
            digestBudgetWindow: oneDay,
            maximumDigestsPerWindow: 4,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await restartedRuntime.processIfNeeded(now: recoveryNow)

        let restartedRequests = await restartedProvider.requests
        XCTAssertTrue(restartedRequests.isEmpty)
        let restartedDeadline = await restartedRuntime.scheduledDeadlineForTesting()
        XCTAssertEqual(restartedDeadline, expectedDeadline)
        let restartedSchedule = try XCTUnwrap(
            restartedStore.loadDigestScheduleState()
        )
        XCTAssertEqual(restartedSchedule, recoveredSchedule)
    }

    func testLegacyReceiptWithStaleSameCountScheduleChargesRecoverySuccess() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let priorDigestAt = clock.now().addingTimeInterval(-(6 * 60 * 60))
        let fixture = try await makeArchivedDigestClaimRecoveryFixture(
            directory: directory,
            timestamp: clock.now(),
            generated: "## Global Style\n- legacy stale schedule"
        )
        try writeLegacyDigestArchiveReceipt(for: fixture.claim, in: directory)
        try writeLegacyDigestSchedule(
            lastSuccessfulDigestAt: priorDigestAt,
            pendingEventCount: 0,
            in: directory
        )
        XCTAssertEqual(try fixture.eventStore.inventory().eventCount, 0)

        clock.advance(by: 120)
        let recoveredDigestAt = clock.now()
        let recoveryProbe = EnvironmentDocumentStoreTestProbe()
        recoveryProbe.failNextClaimClears(1)
        let recoveryStore = EnvironmentDocumentStore(
            fileURL: fixture.environmentURL,
            testProbe: recoveryProbe
        )
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: fixture.eventStore,
            environmentStore: recoveryStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: recoveredDigestAt)

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        let upgradedReceipt = try XCTUnwrap(recoveryStore.loadDigestArchiveReceipt())
        XCTAssertEqual(upgradedReceipt.successfulDigestAt, recoveredDigestAt)
        let schedule = try XCTUnwrap(recoveryStore.loadDigestScheduleState())
        XCTAssertEqual(
            schedule.successfulDigestTimestamps,
            [priorDigestAt, recoveredDigestAt]
        )
        XCTAssertEqual(schedule.lastSuccessfulDigestAt, recoveredDigestAt)
    }

    func testLegacyReceiptWithRecordedScheduleSuccessChargesOnlyOnceAcrossRecovery() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let persistedDigestAt = clock.now()
        let fixture = try await makeArchivedDigestClaimRecoveryFixture(
            directory: directory,
            timestamp: persistedDigestAt,
            generated: "## Global Style\n- legacy recorded schedule"
        )
        try writeLegacyDigestArchiveReceipt(for: fixture.claim, in: directory)
        try writeLegacyDigestSchedule(
            lastSuccessfulDigestAt: persistedDigestAt,
            pendingEventCount: 0,
            in: directory
        )

        clock.advance(by: 120)
        let firstRecoveryDigestAt = clock.now()
        let recoveryProbe = EnvironmentDocumentStoreTestProbe()
        recoveryProbe.failNextClaimClears(1)
        let recoveryStore = EnvironmentDocumentStore(
            fileURL: fixture.environmentURL,
            testProbe: recoveryProbe
        )
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: fixture.eventStore,
            environmentStore: recoveryStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: firstRecoveryDigestAt)

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        let upgradedReceipt = try XCTUnwrap(recoveryStore.loadDigestArchiveReceipt())
        XCTAssertEqual(upgradedReceipt.successfulDigestAt, firstRecoveryDigestAt)
        let scheduleAfterFirstRecovery = try XCTUnwrap(
            recoveryStore.loadDigestScheduleState()
        )
        XCTAssertEqual(
            scheduleAfterFirstRecovery.successfulDigestTimestamps,
            [persistedDigestAt, firstRecoveryDigestAt]
        )

        clock.advance(by: 120)
        let secondRecoveryDigestAt = clock.now()
        let secondProvider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must still not run"
        )
        let secondRecoveryProbe = EnvironmentDocumentStoreTestProbe()
        secondRecoveryProbe.failNextClaimClears(1)
        let secondStore = EnvironmentDocumentStore(
            fileURL: fixture.environmentURL,
            testProbe: secondRecoveryProbe
        )
        let secondRuntime = AIContextMemoryRuntime(
            provider: secondProvider,
            eventStore: TypingEventStore(
                eventsDirectoryURL: directory.appendingPathComponent("events")
            ),
            environmentStore: secondStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await secondRuntime.processIfNeeded(now: secondRecoveryDigestAt)

        let secondRequests = await secondProvider.requests
        XCTAssertTrue(secondRequests.isEmpty)
        XCTAssertEqual(try secondStore.loadDigestClaim(), fixture.claim)
        let retainedReceipt = try XCTUnwrap(secondStore.loadDigestArchiveReceipt())
        XCTAssertEqual(retainedReceipt.successfulDigestAt, firstRecoveryDigestAt)
        let scheduleAfterSecondRecovery = try XCTUnwrap(
            secondStore.loadDigestScheduleState()
        )
        XCTAssertEqual(
            scheduleAfterSecondRecovery.successfulDigestTimestamps,
            [persistedDigestAt, firstRecoveryDigestAt]
        )

        clock.advance(by: 120)
        let thirdProvider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must never run"
        )
        let thirdStore = EnvironmentDocumentStore(fileURL: fixture.environmentURL)
        let thirdRuntime = AIContextMemoryRuntime(
            provider: thirdProvider,
            eventStore: TypingEventStore(
                eventsDirectoryURL: directory.appendingPathComponent("events")
            ),
            environmentStore: thirdStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await thirdRuntime.processIfNeeded(now: clock.now())

        let thirdRequests = await thirdProvider.requests
        XCTAssertTrue(thirdRequests.isEmpty)
        XCTAssertNil(try thirdStore.loadDigestClaim())
        XCTAssertNil(try thirdStore.loadDigestArchiveReceipt())
        let finalSchedule = try XCTUnwrap(thirdStore.loadDigestScheduleState())
        XCTAssertEqual(
            finalSchedule.successfulDigestTimestamps,
            [persistedDigestAt, firstRecoveryDigestAt]
        )
        XCTAssertEqual(finalSchedule.lastSuccessfulDigestAt, firstRecoveryDigestAt)
    }

    func testLegacyReceiptWithoutScheduleUsesRecoveryTime() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let fixture = try await makeArchivedDigestClaimRecoveryFixture(
            directory: directory,
            timestamp: clock.now(),
            generated: "## Global Style\n- legacy recovery time"
        )
        try writeLegacyDigestArchiveReceipt(for: fixture.claim, in: directory)

        clock.advance(by: 120)
        let recoveredDigestAt = clock.now()
        let recoveryProbe = EnvironmentDocumentStoreTestProbe()
        recoveryProbe.failNextClaimClears(1)
        let recoveryStore = EnvironmentDocumentStore(
            fileURL: fixture.environmentURL,
            testProbe: recoveryProbe
        )
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: fixture.eventStore,
            environmentStore: recoveryStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: recoveredDigestAt)

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        let upgradedReceipt = try XCTUnwrap(recoveryStore.loadDigestArchiveReceipt())
        XCTAssertEqual(upgradedReceipt.successfulDigestAt, recoveredDigestAt)
        let schedule = try XCTUnwrap(recoveryStore.loadDigestScheduleState())
        XCTAssertEqual(schedule.successfulDigestTimestamps, [recoveredDigestAt])
        XCTAssertEqual(schedule.lastSuccessfulDigestAt, recoveredDigestAt)
    }

    func testScheduleWriteFailureRecoversReceiptTimestampIntoOneBudgetSlot() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let successfulDigestAt = clock.now()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: environmentURL,
            testProbe: environmentProbe
        )
        let provider = SuspendedDigestLLMProvider()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        let firstDigest = Task {
            await runtime.record(
                makeContextEvent(
                    timestamp: successfulDigestAt,
                    rawInput: "claimed",
                    committedText: "已声明"
                )
            )
        }
        try await waitUntilProviderReceivesRequest(provider)
        try await eventStore.append(
            makeContextEvent(
                timestamp: successfulDigestAt,
                rawInput: "tail",
                committedText: "尾部"
            )
        )
        environmentProbe.failNextScheduleWrites(1)
        await provider.finish(generatedMarkdown: "## Global Style\n- receipt timestamp")
        await firstDigest.value

        let initialRequests = await provider.requests
        XCTAssertEqual(initialRequests.count, 1)
        let receipt = try XCTUnwrap(environmentStore.loadDigestArchiveReceipt())
        XCTAssertEqual(receipt.successfulDigestAt, successfulDigestAt)
        let scheduleBeforeRecovery = try XCTUnwrap(
            environmentStore.loadDigestScheduleState()
        )
        XCTAssertTrue(scheduleBeforeRecovery.successfulDigestTimestamps.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("ENV.digest-claim.json").path
            )
        )

        clock.advance(by: 120)
        let recoveryProvider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let restartedRuntime = AIContextMemoryRuntime(
            provider: recoveryProvider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await restartedRuntime.processIfNeeded(now: clock.now())

        let recoveryRequests = await recoveryProvider.requests
        XCTAssertTrue(recoveryRequests.isEmpty)
        let scheduleAfterRecovery = try XCTUnwrap(
            EnvironmentDocumentStore(fileURL: environmentURL).loadDigestScheduleState()
        )
        XCTAssertEqual(scheduleAfterRecovery.successfulDigestTimestamps, [successfulDigestAt])
        XCTAssertEqual(scheduleAfterRecovery.lastSuccessfulDigestAt, successfulDigestAt)
        let pendingAfterRecovery = try await eventStore.pendingEvents()
        XCTAssertEqual(pendingAfterRecovery.map(\.rawInput), ["tail"])
    }

    func testArchiveReceiptWriteFailureRecoversFromProcessedContentWithoutProviderRetry() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let initialDigestAt = clock.now()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL, testProbe: environmentProbe)
        let provider = SuspendedDigestLLMProvider()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        let firstDigest = Task {
            await runtime.record(
                makeContextEvent(
                    timestamp: initialDigestAt,
                    rawInput: "claimed",
                    committedText: "已声明"
                )
            )
        }
        try await waitUntilProviderReceivesRequest(provider)
        try await eventStore.append(
            makeContextEvent(
                timestamp: initialDigestAt,
                rawInput: "tail",
                committedText: "尾部"
            )
        )
        environmentProbe.failNextArchiveReceiptWrites(1)
        await provider.finish(generatedMarkdown: "## Global Style\n- receipt recovery")
        await firstDigest.value

        let initialRequests = await provider.requests
        let pendingAfterFailure = try await eventStore.pendingEvents()
        XCTAssertEqual(initialRequests.count, 1)
        XCTAssertEqual(pendingAfterFailure.map(\.rawInput), ["tail"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ENV.digest-claim.json").path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("ENV.digest-archive-receipt.json").path
            )
        )
        let scheduleBeforeRecovery = try XCTUnwrap(
            environmentStore.loadDigestScheduleState()
        )
        XCTAssertTrue(scheduleBeforeRecovery.successfulDigestTimestamps.isEmpty)

        clock.advance(by: 120)
        let recoveredDigestAt = clock.now()
        let recoveryProbe = EnvironmentDocumentStoreTestProbe()
        recoveryProbe.failNextClaimClears(1)
        let recoveryProvider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let restartedRuntime = AIContextMemoryRuntime(
            provider: recoveryProvider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(
                fileURL: environmentURL,
                testProbe: recoveryProbe
            ),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )
        await restartedRuntime.processIfNeeded(now: clock.now())

        let recoveryRequests = await recoveryProvider.requests
        XCTAssertTrue(recoveryRequests.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("ENV.digest-claim.json").path
            )
        )
        let receiptAfterFirstRecovery = try XCTUnwrap(
            EnvironmentDocumentStore(fileURL: environmentURL).loadDigestArchiveReceipt()
        )
        XCTAssertEqual(receiptAfterFirstRecovery.successfulDigestAt, recoveredDigestAt)
        let scheduleAfterFirstRecovery = try XCTUnwrap(
            EnvironmentDocumentStore(fileURL: environmentURL).loadDigestScheduleState()
        )
        XCTAssertEqual(scheduleAfterFirstRecovery.successfulDigestTimestamps, [recoveredDigestAt])

        clock.advance(by: 120)
        let secondRecoveryProvider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must still not run"
        )
        let secondRestart = AIContextMemoryRuntime(
            provider: secondRecoveryProvider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )
        await secondRestart.processIfNeeded(now: clock.now())

        let secondRecoveryRequests = await secondRecoveryProvider.requests
        let pendingAfterRecovery = try await eventStore.pendingEvents()
        XCTAssertTrue(secondRecoveryRequests.isEmpty)
        XCTAssertEqual(pendingAfterRecovery.map(\.rawInput), ["tail"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("ENV.digest-claim.json").path
            )
        )
        let finalSchedule = try XCTUnwrap(
            EnvironmentDocumentStore(fileURL: environmentURL).loadDigestScheduleState()
        )
        XCTAssertEqual(finalSchedule.successfulDigestTimestamps, [recoveredDigestAt])
        XCTAssertEqual(finalSchedule.lastSuccessfulDigestAt, recoveredDigestAt)
    }

    func testArchiveReceiptCleanupFailureDoesNotConsumeAnotherBudgetSlot() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let successfulDigestAt = clock.now()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let provider = SuspendedDigestLLMProvider()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(
                fileURL: environmentURL,
                testProbe: environmentProbe
            ),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        let firstDigest = Task {
            await runtime.record(
                makeContextEvent(
                    timestamp: successfulDigestAt,
                    rawInput: "cleanup",
                    committedText: "清理回执"
                )
            )
        }
        try await waitUntilProviderReceivesRequest(provider)
        environmentProbe.failNextArchiveReceiptClears(1)
        await provider.finish(generatedMarkdown: "## Global Style\n- receipt cleanup")
        await firstDigest.value

        let initialRequests = await provider.requests
        XCTAssertEqual(initialRequests.count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("ENV.digest-claim.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("ENV.digest-archive-receipt.json").path
            )
        )
        let scheduleBeforeRestart = try XCTUnwrap(
            EnvironmentDocumentStore(fileURL: environmentURL).loadDigestScheduleState()
        )
        XCTAssertEqual(scheduleBeforeRestart.successfulDigestTimestamps, [successfulDigestAt])

        clock.advance(by: 120)
        let recoveryProvider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let restartedRuntime = AIContextMemoryRuntime(
            provider: recoveryProvider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await restartedRuntime.processIfNeeded(now: clock.now())

        let recoveryRequests = await recoveryProvider.requests
        XCTAssertTrue(recoveryRequests.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("ENV.digest-archive-receipt.json").path
            )
        )
        let scheduleAfterRestart = try XCTUnwrap(
            EnvironmentDocumentStore(fileURL: environmentURL).loadDigestScheduleState()
        )
        XCTAssertEqual(scheduleAfterRestart.successfulDigestTimestamps, [successfulDigestAt])
        XCTAssertEqual(scheduleAfterRestart.lastSuccessfulDigestAt, successfulDigestAt)
    }

    func testCorruptSameSizeProcessedArchiveBlocksReceiptRecovery() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let provider = SuspendedDigestLLMProvider()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: environmentURL,
                testProbe: environmentProbe
            ),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )

        let firstDigest = Task {
            await runtime.record(makeContextEvent(rawInput: "claimed", committedText: "已声明"))
        }
        try await waitUntilProviderReceivesRequest(provider)
        try await eventStore.append(makeContextEvent(rawInput: "tail", committedText: "尾部"))
        environmentProbe.failNextArchiveReceiptWrites(1)
        await provider.finish(generatedMarkdown: "## Global Style\n- corrupt recovery")
        await firstDigest.value

        let processedDirectory = eventsDirectory.appendingPathComponent("processed")
        let archives = try FileManager.default.contentsOfDirectory(
            at: processedDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("typing-events-") }
        let archiveURL = try XCTUnwrap(archives.first)
        var archiveData = try Data(contentsOf: archiveURL)
        XCTAssertFalse(archiveData.isEmpty)
        archiveData[archiveData.startIndex] ^= 0x01
        try archiveData.write(to: archiveURL, options: .atomic)

        let recoveryProvider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let restartedRuntime = AIContextMemoryRuntime(
            provider: recoveryProvider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )
        await restartedRuntime.processIfNeeded()

        let recoveryRequests = await recoveryProvider.requests
        let pendingAfterRecovery = try await eventStore.pendingEvents()
        XCTAssertTrue(recoveryRequests.isEmpty)
        XCTAssertEqual(pendingAfterRecovery.map(\.rawInput), ["tail"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ENV.digest-claim.json").path))
    }

    func testClaimBeforeEnvironmentCommitBlocksRestartWithoutProviderRetry() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        try await eventStore.append(
            makeContextEvent(rawInput: "claimed-before-env", committedText: "提交前声明")
        )
        let snapshot = try eventStore.pendingDigestSnapshot()
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        _ = try environmentStore.loadSnapshot()
        let claim = EnvironmentDigestClaim(
            claimedPrefixSHA256: AIDocumentSnapshot.hash(snapshot.rawContent),
            claimedPrefixByteCount: snapshot.rawData.count,
            claimedEventCount: snapshot.claimedEventCount,
            generatedSHA256: AIDocumentSnapshot.hash("## Global Style\n- not committed"),
            providerGeneration: 0
        )
        try environmentStore.saveDigestClaim(claim)

        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let restartedRuntime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )
        await restartedRuntime.record(
            makeContextEvent(rawInput: "must-be-dropped", committedText: "不得追加")
        )

        let requests = await provider.requests
        let pending = try await eventStore.pendingEvents()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(pending.map(\.rawInput), ["claimed-before-env"])
        XCTAssertEqual(try environmentStore.loadDigestClaim(), claim)
    }

    func testBlockedPersistedClaimRecoveryIsSingleFlightAcrossConcurrentRecords() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        try await eventStore.append(
            makeContextEvent(rawInput: "single-flight-claimed", committedText: "已声明")
        )
        let snapshot = try eventStore.pendingDigestSnapshot()
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md"),
            testProbe: environmentProbe
        )
        _ = try environmentStore.loadSnapshot()
        let expectedGenerated = "## Global Style\n- expected after repair"
        let claim = EnvironmentDigestClaim(
            claimedPrefixSHA256: AIDocumentSnapshot.hash(snapshot.rawContent),
            claimedPrefixByteCount: snapshot.rawData.count,
            claimedEventCount: snapshot.claimedEventCount,
            generatedSHA256: AIDocumentSnapshot.hash(expectedGenerated),
            providerGeneration: 0
        )
        try environmentStore.saveDigestClaim(claim)
        let readsBeforeRecovery = environmentProbe.environmentDocumentReadCount
        let clock = ManualContextClock()
        let sleeper = ControlledContextDeadlineSleeper()
        let runtimeProbe = AIContextMemoryRuntimeTestProbe(
            pausesBeforeClaimRecoveryGatePreflight: true
        )
        let gateProbe = ProviderRequestGateTestProbe()
        let diagnostics = ContextMemoryDiagnosticProbe()
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            diagnosticSink: { diagnostics.record($0) },
            requestGate: ProviderRequestGate(testProbe: gateProbe),
            nowProvider: { clock.now() },
            testProbe: runtimeProbe,
            claimRecoveryBackoff: 60,
            claimRecoverySleeper: { nanoseconds in
                await sleeper.suspend(nanoseconds: nanoseconds)
            }
        )

        let owner = Task { await runtime.processIfNeeded(now: clock.now()) }
        try await waitUntil { await runtimeProbe.claimRecoveryGatePreflightPauseCount == 1 }
        let firstRecord = Task {
            await runtime.record(
                makeContextEvent(rawInput: "single-flight-dropped-1", committedText: "不得追加一")
            )
        }
        let secondRecord = Task {
            await runtime.record(
                makeContextEvent(rawInput: "single-flight-dropped-2", committedText: "不得追加二")
            )
        }
        let concurrentProcess = Task { await runtime.processIfNeeded(now: clock.now()) }
        try await waitUntil { await runtime.claimRecoveryWaiterCountForTesting() == 3 }

        let attemptsWhilePaused = await runtimeProbe.claimRecoveryAttemptCount
        let claimLoadsWhilePaused = await runtimeProbe.claimRecoveryClaimLoadCount
        XCTAssertEqual(attemptsWhilePaused, 1)
        XCTAssertEqual(claimLoadsWhilePaused, 0)
        XCTAssertEqual(gateProbe.preflightCheckCount, 0)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, readsBeforeRecovery)
        let requestsWhileRecoveryPaused = await provider.requests
        XCTAssertTrue(requestsWhileRecoveryPaused.isEmpty)

        await runtimeProbe.releaseClaimRecoveryGatePreflight()
        await owner.value
        await firstRecord.value
        await secondRecord.value
        await concurrentProcess.value
        try await waitUntil { await sleeper.suspensionCount == 1 }

        let attemptsAfterFailure = await runtimeProbe.claimRecoveryAttemptCount
        let claimLoadsAfterFailure = await runtimeProbe.claimRecoveryClaimLoadCount
        let retrySchedules = await runtimeProbe.claimRecoveryRetryScheduleCount
        let pendingAfterFailure = try await eventStore.pendingEvents()
        XCTAssertEqual(attemptsAfterFailure, 1)
        XCTAssertEqual(claimLoadsAfterFailure, 1)
        XCTAssertEqual(retrySchedules, 1)
        XCTAssertEqual(gateProbe.preflightCheckCount, 1)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, readsBeforeRecovery + 1)
        XCTAssertEqual(pendingAfterFailure.map(\.rawInput), ["single-flight-claimed"])
        let requestsAfterBlockedRecovery = await provider.requests
        XCTAssertTrue(requestsAfterBlockedRecovery.isEmpty)
        XCTAssertEqual(diagnostics.stageCount("context_claim_recovery_blocked"), 1)
        let diagnosticLines = diagnostics.lines.joined()
        XCTAssertFalse(diagnosticLines.contains("single-flight-claimed"))
        XCTAssertFalse(diagnosticLines.contains("single-flight-dropped"))
        XCTAssertFalse(diagnosticLines.contains(claim.claimedPrefixSHA256))

        _ = try environmentStore.replaceGeneratedSection(with: expectedGenerated)
        clock.advance(by: 60)
        await sleeper.releaseNext()
        try await waitUntil { (try? environmentStore.loadDigestClaim()) == nil }
    }

    func testSuccessfulPersistedClaimRecoveryReleasesWaitingRecordsToAppend() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        try await eventStore.append(
            makeContextEvent(rawInput: "single-flight-success-claimed", committedText: "已提交")
        )
        let snapshot = try eventStore.pendingDigestSnapshot()
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md"),
            testProbe: environmentProbe
        )
        let generated = "## Global Style\n- committed before restart"
        _ = try environmentStore.replaceGeneratedSection(with: generated)
        try environmentStore.saveDigestClaim(
            EnvironmentDigestClaim(
                claimedPrefixSHA256: AIDocumentSnapshot.hash(snapshot.rawContent),
                claimedPrefixByteCount: snapshot.rawData.count,
                claimedEventCount: snapshot.claimedEventCount,
                generatedSHA256: AIDocumentSnapshot.hash(generated),
                providerGeneration: 0
            )
        )
        let readsBeforeRecovery = environmentProbe.environmentDocumentReadCount
        let runtimeProbe = AIContextMemoryRuntimeTestProbe(
            pausesBeforeClaimRecoveryGatePreflight: true
        )
        let gateProbe = ProviderRequestGateTestProbe()
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 50,
            minimumInterval: 600,
            diagnosticSink: { _ in },
            requestGate: ProviderRequestGate(testProbe: gateProbe),
            testProbe: runtimeProbe
        )

        let owner = Task { await runtime.processIfNeeded() }
        try await waitUntil { await runtimeProbe.claimRecoveryGatePreflightPauseCount == 1 }
        let firstRecord = Task {
            await runtime.record(
                makeContextEvent(rawInput: "single-flight-appended-1", committedText: "追加一")
            )
        }
        let secondRecord = Task {
            await runtime.record(
                makeContextEvent(rawInput: "single-flight-appended-2", committedText: "追加二")
            )
        }
        let concurrentProcess = Task { await runtime.processIfNeeded() }
        try await waitUntil { await runtime.claimRecoveryWaiterCountForTesting() == 3 }

        let attemptsWhilePaused = await runtimeProbe.claimRecoveryAttemptCount
        let claimLoadsWhilePaused = await runtimeProbe.claimRecoveryClaimLoadCount
        XCTAssertEqual(attemptsWhilePaused, 1)
        XCTAssertEqual(claimLoadsWhilePaused, 0)
        XCTAssertEqual(gateProbe.preflightCheckCount, 0)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, readsBeforeRecovery)

        await runtimeProbe.releaseClaimRecoveryGatePreflight()
        await owner.value
        await firstRecord.value
        await secondRecord.value
        await concurrentProcess.value

        let pendingAfterRecovery = try await eventStore.pendingEvents()
        let pendingInputs = pendingAfterRecovery.map(\.rawInput)
        let attemptsAfterRecovery = await runtimeProbe.claimRecoveryAttemptCount
        let claimLoadsAfterRecovery = await runtimeProbe.claimRecoveryClaimLoadCount
        let retrySchedules = await runtimeProbe.claimRecoveryRetryScheduleCount
        XCTAssertEqual(attemptsAfterRecovery, 1)
        XCTAssertEqual(claimLoadsAfterRecovery, 1)
        XCTAssertEqual(retrySchedules, 0)
        XCTAssertEqual(gateProbe.preflightCheckCount, 1)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, readsBeforeRecovery + 1)
        XCTAssertEqual(pendingInputs.count, 2)
        XCTAssertEqual(
            Set(pendingInputs),
            Set(["single-flight-appended-1", "single-flight-appended-2"])
        )
        XCTAssertNil(try environmentStore.loadDigestClaim())
        let providerRequestsAfterRecovery = await provider.requests
        XCTAssertTrue(providerRequestsAfterRecovery.isEmpty)
    }

    func testBlockedClaimRecoveryCoalescesRecordsAndRetriesOncePerDeadline() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        try await eventStore.append(
            makeContextEvent(rawInput: "claimed-private-prefix", committedText: "声明内容")
        )
        let snapshot = try eventStore.pendingDigestSnapshot()
        let environmentProbe = EnvironmentDocumentStoreTestProbe()
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md"),
            testProbe: environmentProbe
        )
        _ = try environmentStore.loadSnapshot()
        let repairedGenerated = "## Global Style\n- repaired claim"
        let claim = EnvironmentDigestClaim(
            claimedPrefixSHA256: AIDocumentSnapshot.hash(snapshot.rawContent),
            claimedPrefixByteCount: snapshot.rawData.count,
            claimedEventCount: snapshot.claimedEventCount,
            generatedSHA256: AIDocumentSnapshot.hash(repairedGenerated),
            providerGeneration: 0
        )
        try environmentStore.saveDigestClaim(claim)
        let environmentReadsBeforeRecovery = environmentProbe.environmentDocumentReadCount
        let clock = ManualContextClock()
        let sleeper = ControlledContextDeadlineSleeper()
        let runtimeProbe = AIContextMemoryRuntimeTestProbe()
        let diagnostics = ContextMemoryDiagnosticProbe()
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            diagnosticSink: { diagnostics.record($0) },
            requestGate: ProviderRequestGate(),
            nowProvider: { clock.now() },
            testProbe: runtimeProbe,
            claimRecoveryBackoff: 60,
            claimRecoverySleeper: { nanoseconds in
                await sleeper.suspend(nanoseconds: nanoseconds)
            }
        )

        await runtime.record(
            makeContextEvent(rawInput: "first-dropped-private", committedText: "不得追加")
        )
        try await waitUntil { await sleeper.suspensionCount == 1 }
        let attemptsAfterFirstFailure = await runtimeProbe.claimRecoveryAttemptCount
        XCTAssertEqual(attemptsAfterFirstFailure, 1)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, environmentReadsBeforeRecovery + 1)

        for index in 0..<100 {
            await runtime.record(
                makeContextEvent(rawInput: "dropped-\(index)", committedText: "不得追加")
            )
        }

        let attemptsDuringBackoff = await runtimeProbe.claimRecoveryAttemptCount
        let schedulesDuringBackoff = await runtimeProbe.claimRecoveryRetryScheduleCount
        let pendingDuringBackoff = try await eventStore.pendingEvents()
        XCTAssertEqual(attemptsDuringBackoff, 1)
        XCTAssertEqual(schedulesDuringBackoff, 1)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, environmentReadsBeforeRecovery + 1)
        XCTAssertEqual(pendingDuringBackoff.map(\.rawInput), ["claimed-private-prefix"])
        let requestsDuringBackoff = await provider.requests
        XCTAssertTrue(requestsDuringBackoff.isEmpty)

        clock.advance(by: 60)
        await sleeper.releaseNext()
        try await waitUntil { await runtimeProbe.claimRecoveryAttemptCount == 2 }
        try await waitUntil { await sleeper.suspensionCount == 2 }
        try await waitUntil { await runtimeProbe.claimRecoveryRetryScheduleCount == 2 }
        let schedulesAfterDeadline = await runtimeProbe.claimRecoveryRetryScheduleCount
        XCTAssertEqual(schedulesAfterDeadline, 2)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, environmentReadsBeforeRecovery + 2)

        _ = try environmentStore.replaceGeneratedSection(with: repairedGenerated)
        let environmentReadsBeforeRepairWake = environmentProbe.environmentDocumentReadCount
        clock.advance(by: 60)
        await sleeper.releaseNext()
        try await waitUntil { (try? environmentStore.loadDigestClaim()) == nil }

        let attemptsAfterRepair = await runtimeProbe.claimRecoveryAttemptCount
        let pendingAfterRepair = try await eventStore.pendingEvents()
        XCTAssertEqual(attemptsAfterRepair, 3)
        XCTAssertEqual(environmentProbe.environmentDocumentReadCount, environmentReadsBeforeRepairWake + 1)
        XCTAssertTrue(pendingAfterRepair.isEmpty)
        let requestsAfterRepair = await provider.requests
        XCTAssertTrue(requestsAfterRepair.isEmpty)
        XCTAssertEqual(diagnostics.stageCount("context_claim_recovery_blocked"), 2)
        let diagnosticLines = diagnostics.lines.joined()
        XCTAssertFalse(diagnosticLines.contains("claimed-private-prefix"))
        XCTAssertFalse(diagnosticLines.contains("dropped-"))
        XCTAssertFalse(diagnosticLines.contains(claim.claimedPrefixSHA256))
    }

    func testRestartedRecordRecoversClaimBeforeBacklogCompaction() async throws {
        let directory = makeTemporaryDirectory()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let fixedNow = Date()
        var policy = TypingEventRetentionPolicy.default
        policy.processedMaximumFileCount = 2
        policy.processedMaximumByteCount = 1_000_000
        let eventStore = TypingEventStore(
            eventsDirectoryURL: eventsDirectory,
            retentionPolicy: policy,
            now: { fixedNow }
        )
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        let generated = "## Global Style\n- committed before restart"

        try await eventStore.append(
            makeContextEvent(rawInput: "claimed-prefix", committedText: "已声明前缀")
        )
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        _ = try environmentStore.replaceGeneratedSection(with: generated)
        try environmentStore.saveDigestClaim(
            EnvironmentDigestClaim(
                claimedPrefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
                claimedPrefixByteCount: claimedSnapshot.rawData.count,
                claimedEventCount: claimedSnapshot.claimedEventCount,
                generatedSHA256: AIDocumentSnapshot.hash(generated),
                providerGeneration: 0
            )
        )
        for index in 0..<499 {
            try await eventStore.append(
                makeContextEvent(rawInput: "tail-\(index)", committedText: "尾部\(index)")
            )
        }
        XCTAssertEqual(try eventStore.inventory().eventCount, 500)
        let seededArchives = try seedProcessedRetentionArchives(
            at: eventsDirectory.appendingPathComponent("processed"),
            now: fixedNow
        )

        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must not run")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: TypingEventStore(
                eventsDirectoryURL: eventsDirectory,
                retentionPolicy: policy,
                now: { fixedNow }
            ),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 600,
            requestGate: ProviderRequestGate(),
            nowProvider: { fixedNow }
        )

        await runtime.record(
            makeContextEvent(rawInput: "first-after-restart", committedText: "重启后首次")
        )

        let pending = try await TypingEventStore(
            eventsDirectoryURL: eventsDirectory
        ).pendingEvents()
        let providerRequests = await provider.requests
        XCTAssertTrue(providerRequests.isEmpty)
        XCTAssertEqual(pending.count, 500)
        XCTAssertEqual(pending.first?.rawInput, "tail-0")
        XCTAssertEqual(pending.last?.rawInput, "first-after-restart")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("ENV.digest-claim.json").path
            )
        )
        XCTAssertTrue(
            eventStore.hasProcessedArchive(
                prefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
                byteCount: claimedSnapshot.rawData.count
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: seededArchives.expired.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: seededArchives.oldestRecent.path))
        let processedArchives = try FileManager.default.contentsOfDirectory(
            at: eventsDirectory.appendingPathComponent("processed"),
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.lastPathComponent.hasPrefix("typing-events-") }
        let processedBytes = try processedArchives.reduce(0) { partial, url in
            partial + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertLessThanOrEqual(processedArchives.count, policy.processedMaximumFileCount)
        XCTAssertLessThanOrEqual(processedBytes, policy.processedMaximumByteCount)
    }

    func testCorruptScheduleStateDefersBatchAcrossRestart() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        try await eventStore.append(makeContextEvent(rawInput: "scheduled", committedText: "排程"))
        try Data("corrupt schedule".utf8).write(
            to: directory.appendingPathComponent("ENV.digest-schedule.json"),
            options: .atomic
        )

        let firstProvider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- first")
        let firstRuntime = AIContextMemoryRuntime(
            provider: firstProvider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 10,
            maximumPendingAge: 10,
            digestBudgetWindow: 10,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )
        await firstRuntime.processIfNeeded(now: clock.now())

        let firstRequests = await firstProvider.requests
        XCTAssertTrue(firstRequests.isEmpty)
        let repairedSchedule = try XCTUnwrap(
            EnvironmentDocumentStore(fileURL: environmentURL).loadDigestScheduleState()
        )
        XCTAssertEqual(repairedSchedule.pendingSince, clock.now())
        XCTAssertNil(repairedSchedule.lastSuccessfulDigestAt)
        let nextEligibleAt = try XCTUnwrap(repairedSchedule.nextEligibleAt)
        XCTAssertEqual(
            nextEligibleAt.timeIntervalSince(clock.now()),
            10,
            accuracy: 0.001
        )

        let secondProvider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- recovered")
        let restartedRuntime = AIContextMemoryRuntime(
            provider: secondProvider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 10,
            maximumPendingAge: 10,
            digestBudgetWindow: 10,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )
        await restartedRuntime.processIfNeeded(now: clock.now())
        let restartRequests = await secondProvider.requests
        XCTAssertTrue(restartRequests.isEmpty)

        clock.advance(by: 11)
        await restartedRuntime.processIfNeeded(now: clock.now())
        let requestsAfterDeadline = await secondProvider.requests
        XCTAssertEqual(requestsAfterDeadline.count, 1)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
    }

    func testConservativeScheduleRepairBlocksRecordRecoveryAcrossRestartUntilDeadline() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let interval: TimeInterval = 600
        let fixture = try await makeArchivedDigestClaimRecoveryFixture(
            directory: directory,
            timestamp: clock.now(),
            generated: "## Global Style\n- repaired schedule claim"
        )
        try writeLegacyDigestArchiveReceipt(for: fixture.claim, in: directory)
        let receiptBeforeRepair = try XCTUnwrap(
            fixture.environmentStore.loadDigestArchiveReceipt()
        )
        try Data("corrupt schedule".utf8).write(
            to: directory.appendingPathComponent("ENV.digest-schedule.json"),
            options: .atomic
        )
        let eventStoreProbe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: eventStoreProbe
        )
        let runtimeProbe = AIContextMemoryRuntimeTestProbe()
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: fixture.environmentURL
            ),
            batchSize: 1,
            minimumInterval: interval,
            maximumPendingAge: interval,
            digestBudgetWindow: interval,
            diagnosticSink: { _ in },
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now,
            testProbe: runtimeProbe
        )

        await runtime.record(
            makeContextEvent(
                timestamp: clock.now(),
                rawInput: "must-not-append-before-repair-deadline",
                committedText: "修复期限前不得追加"
            )
        )

        let expectedDeadline = clock.now().addingTimeInterval(interval)
        let claimLoadsBeforeDeadline = await runtimeProbe.claimRecoveryClaimLoadCount
        let providerRequestsBeforeDeadline = await provider.requests
        XCTAssertEqual(claimLoadsBeforeDeadline, 0)
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, 0)
        XCTAssertTrue(providerRequestsBeforeDeadline.isEmpty)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
        XCTAssertEqual(
            try fixture.environmentStore.loadDigestClaim(),
            fixture.claim
        )
        XCTAssertEqual(
            try fixture.environmentStore.loadDigestArchiveReceipt(),
            receiptBeforeRepair
        )
        let repairedSchedule = try XCTUnwrap(
            fixture.environmentStore.loadDigestScheduleState()
        )
        XCTAssertEqual(repairedSchedule.pendingSince, clock.now())
        XCTAssertNil(repairedSchedule.lastSuccessfulDigestAt)
        XCTAssertEqual(repairedSchedule.nextEligibleAt, expectedDeadline)
        XCTAssertEqual(repairedSchedule.pendingEventCount, 0)
        XCTAssertTrue(repairedSchedule.successfulDigestTimestamps.isEmpty)
        let firstDeadline = await runtime.scheduledDeadlineForTesting()
        XCTAssertEqual(firstDeadline, expectedDeadline)

        let restartedEventStoreProbe = TypingEventStoreTestProbe()
        let restartedRuntimeProbe = AIContextMemoryRuntimeTestProbe()
        let restartedProvider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must still not run"
        )
        let restartedRuntime = AIContextMemoryRuntime(
            provider: restartedProvider,
            eventStore: TypingEventStore(
                eventsDirectoryURL: directory.appendingPathComponent("events"),
                retentionPolicy: .default,
                testProbe: restartedEventStoreProbe
            ),
            environmentStore: EnvironmentDocumentStore(
                fileURL: fixture.environmentURL
            ),
            batchSize: 1,
            minimumInterval: interval,
            maximumPendingAge: interval,
            digestBudgetWindow: interval,
            diagnosticSink: { _ in },
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now,
            testProbe: restartedRuntimeProbe
        )

        await restartedRuntime.processIfNeeded(now: clock.now())

        let restartedClaimLoads = await restartedRuntimeProbe.claimRecoveryClaimLoadCount
        let restartedRequests = await restartedProvider.requests
        XCTAssertEqual(restartedClaimLoads, 0)
        XCTAssertEqual(restartedEventStoreProbe.digestSnapshotDecodeCount, 0)
        XCTAssertTrue(restartedRequests.isEmpty)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
        XCTAssertEqual(
            try fixture.environmentStore.loadDigestClaim(),
            fixture.claim
        )
        XCTAssertEqual(
            try fixture.environmentStore.loadDigestArchiveReceipt(),
            receiptBeforeRepair
        )
        XCTAssertEqual(
            try fixture.environmentStore.loadDigestScheduleState(),
            repairedSchedule
        )
        let restartedDeadline = await restartedRuntime.scheduledDeadlineForTesting()
        XCTAssertEqual(restartedDeadline, expectedDeadline)

        clock.advance(by: interval + 1)
        let recoveryNow = clock.now()
        await restartedRuntime.processIfNeeded(now: recoveryNow)

        let claimLoadsAfterDeadline = await restartedRuntimeProbe.claimRecoveryClaimLoadCount
        let requestsAfterDeadline = await restartedProvider.requests
        XCTAssertEqual(claimLoadsAfterDeadline, 1)
        XCTAssertTrue(requestsAfterDeadline.isEmpty)
        XCTAssertNil(try fixture.environmentStore.loadDigestClaim())
        XCTAssertNil(try fixture.environmentStore.loadDigestArchiveReceipt())
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
        let recoveredSchedule = try XCTUnwrap(
            fixture.environmentStore.loadDigestScheduleState()
        )
        XCTAssertEqual(recoveredSchedule.lastSuccessfulDigestAt, recoveryNow)
        XCTAssertEqual(
            recoveredSchedule.successfulDigestTimestamps,
            [recoveryNow]
        )
        XCTAssertNil(recoveredSchedule.nextEligibleAt)
        let deadlineAfterRecovery = await restartedRuntime.scheduledDeadlineForTesting()
        XCTAssertNil(deadlineAfterRecovery)
    }

    func testConservativeScheduleRepairBlocksProcessClaimRecoveryBeforeDeadline() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let interval: TimeInterval = 600
        let fixture = try await makeArchivedDigestClaimRecoveryFixture(
            directory: directory,
            timestamp: clock.now(),
            generated: "## Global Style\n- semantic repair claim"
        )
        try writeLegacyDigestArchiveReceipt(for: fixture.claim, in: directory)
        let receiptBeforeRepair = try XCTUnwrap(
            fixture.environmentStore.loadDigestArchiveReceipt()
        )
        try fixture.environmentStore.saveDigestScheduleState(
            EnvironmentDigestScheduleState(
                pendingSince: clock.now(),
                lastSuccessfulDigestAt: nil,
                nextEligibleAt: clock.now().addingTimeInterval(-1),
                pendingEventCount: 1,
                successfulDigestTimestamps: []
            )
        )
        let eventStoreProbe = TypingEventStoreTestProbe()
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: .default,
            testProbe: eventStoreProbe
        )
        let runtimeProbe = AIContextMemoryRuntimeTestProbe()
        let provider = DigestLLMProvider(
            generatedMarkdown: "## Global Style\n- must not run"
        )
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(
                fileURL: fixture.environmentURL
            ),
            batchSize: 1,
            minimumInterval: interval,
            maximumPendingAge: interval,
            digestBudgetWindow: interval,
            diagnosticSink: { _ in },
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now,
            testProbe: runtimeProbe
        )

        await runtime.processIfNeeded(now: clock.now())

        let claimLoads = await runtimeProbe.claimRecoveryClaimLoadCount
        let providerRequests = await provider.requests
        XCTAssertEqual(claimLoads, 0)
        XCTAssertEqual(eventStoreProbe.digestSnapshotDecodeCount, 0)
        XCTAssertTrue(providerRequests.isEmpty)
        XCTAssertEqual(try eventStore.inventory().eventCount, 0)
        XCTAssertEqual(
            try fixture.environmentStore.loadDigestClaim(),
            fixture.claim
        )
        XCTAssertEqual(
            try fixture.environmentStore.loadDigestArchiveReceipt(),
            receiptBeforeRepair
        )
        let repairedSchedule = try XCTUnwrap(
            fixture.environmentStore.loadDigestScheduleState()
        )
        XCTAssertEqual(repairedSchedule.pendingSince, clock.now())
        XCTAssertNil(repairedSchedule.lastSuccessfulDigestAt)
        XCTAssertEqual(
            repairedSchedule.nextEligibleAt,
            clock.now().addingTimeInterval(interval)
        )
        XCTAssertEqual(repairedSchedule.pendingEventCount, 0)
        XCTAssertTrue(repairedSchedule.successfulDigestTimestamps.isEmpty)
        let scheduledDeadline = await runtime.scheduledDeadlineForTesting()
        XCTAssertEqual(
            scheduledDeadline,
            clock.now().addingTimeInterval(interval)
        )
    }

    func testLegacyScheduleWithoutDigestHistoryRemainsReadableAndPreservesInterval() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let sixHours: TimeInterval = 6 * 60 * 60
        let now = clock.now()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        try await eventStore.append(
            makeContextEvent(rawInput: "legacy-tail", committedText: "旧排程尾部")
        )
        let legacySchedule: [String: Any] = [
            "pendingSince": now.timeIntervalSinceReferenceDate,
            "lastSuccessfulDigestAt": now.timeIntervalSinceReferenceDate,
            "nextEligibleAt": now.addingTimeInterval(sixHours).timeIntervalSinceReferenceDate,
            "pendingEventCount": 1
        ]
        try JSONSerialization.data(
            withJSONObject: legacySchedule,
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("ENV.digest-schedule.json"),
            options: .atomic
        )
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)

        let decoded = try XCTUnwrap(environmentStore.loadDigestScheduleState())
        XCTAssertTrue(decoded.successfulDigestTimestamps.isEmpty)
        XCTAssertEqual(decoded.lastSuccessfulDigestAt, now)

        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must wait")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: sixHours,
            maximumPendingAge: 24 * 60 * 60,
            digestBudgetWindow: 24 * 60 * 60,
            maximumDigestsPerWindow: 4,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: now)

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(try eventStore.inventory().eventCount, 1)
    }

    func testSemanticallyInvalidScheduleStateRebuildsConservativeDeadline() async throws {
        let invalidStates: [(ManualContextClock, EnvironmentDigestScheduleState)] = (0..<3).map { index in
            let clock = ManualContextClock()
            let now = clock.now()
            let state: EnvironmentDigestScheduleState
            switch index {
            case 0:
                state = EnvironmentDigestScheduleState(
                    pendingSince: now,
                    lastSuccessfulDigestAt: nil,
                    nextEligibleAt: now.addingTimeInterval(-1),
                    pendingEventCount: 1
                )
            case 1:
                state = EnvironmentDigestScheduleState(
                    pendingSince: now.addingTimeInterval(11),
                    lastSuccessfulDigestAt: nil,
                    nextEligibleAt: now.addingTimeInterval(12),
                    pendingEventCount: 1
                )
            default:
                state = EnvironmentDigestScheduleState(
                    pendingSince: nil,
                    lastSuccessfulDigestAt: now,
                    nextEligibleAt: now.addingTimeInterval(10_000),
                    pendingEventCount: 1
                )
            }
            return (clock, state)
        }

        for (clock, state) in invalidStates {
            let directory = makeTemporaryDirectory()
            let eventsDirectory = directory.appendingPathComponent("events")
            let environmentURL = directory.appendingPathComponent("ENV.md")
            let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
            let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
            try await eventStore.append(
                makeContextEvent(rawInput: "semantic-corruption", committedText: "语义损坏")
            )
            try environmentStore.saveDigestScheduleState(state)
            let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- must defer")
            let runtime = AIContextMemoryRuntime(
                provider: provider,
                eventStore: eventStore,
                environmentStore: environmentStore,
                batchSize: 1,
                minimumInterval: 10,
                maximumPendingAge: 10,
                digestBudgetWindow: 10,
                requestGate: ProviderRequestGate(),
                nowProvider: clock.now
            )

            await runtime.processIfNeeded(now: clock.now())

            let providerRequests = await provider.requests
            XCTAssertTrue(providerRequests.isEmpty)
            let repaired = try XCTUnwrap(environmentStore.loadDigestScheduleState())
            XCTAssertEqual(repaired.pendingSince, clock.now())
            XCTAssertNil(repaired.lastSuccessfulDigestAt)
            let repairedNextEligibleAt = try XCTUnwrap(repaired.nextEligibleAt)
            XCTAssertEqual(
                repairedNextEligibleAt.timeIntervalSince(clock.now()),
                10,
                accuracy: 0.001
            )
        }
    }

    func testPendingScheduleWithoutTimeAnchorDefersBatchOnFreshRuntime() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
        try await eventStore.append(
            makeContextEvent(rawInput: "anchorless", committedText: "无时间锚点")
        )
        try environmentStore.saveDigestScheduleState(
            EnvironmentDigestScheduleState(
                pendingSince: nil,
                lastSuccessfulDigestAt: nil,
                nextEligibleAt: nil,
                pendingEventCount: 1
            )
        )
        let provider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- repaired")
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 10,
            maximumPendingAge: 10,
            digestBudgetWindow: 10,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )

        await runtime.processIfNeeded(now: clock.now())

        let requestsBeforeDeadline = await provider.requests
        XCTAssertTrue(requestsBeforeDeadline.isEmpty)
        let repaired = try XCTUnwrap(environmentStore.loadDigestScheduleState())
        XCTAssertEqual(repaired.pendingSince, clock.now())
        let repairedDeadline = try XCTUnwrap(repaired.nextEligibleAt)
        XCTAssertEqual(
            repairedDeadline.timeIntervalSince(clock.now()),
            10,
            accuracy: 0.001
        )

        clock.advance(by: 11)
        await runtime.processIfNeeded(now: clock.now())
        let requestsAfterDeadline = await provider.requests
        XCTAssertEqual(requestsAfterDeadline.count, 1)
    }

    func testPersistedSuccessIntervalStillBlocksBatchTailAfterRuntimeRebuild() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        let eventsDirectory = directory.appendingPathComponent("events")
        let environmentURL = directory.appendingPathComponent("ENV.md")
        let eventStore = TypingEventStore(eventsDirectoryURL: eventsDirectory)
        let firstProvider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- first")
        let firstRuntime = AIContextMemoryRuntime(
            provider: firstProvider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 10,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )
        await firstRuntime.record(makeContextEvent(rawInput: "first", committedText: "第一"))
        for index in 0..<50 {
            try await eventStore.append(makeContextEvent(rawInput: "tail-\(index)", committedText: "尾部\(index)"))
        }

        let secondProvider = DigestLLMProvider(generatedMarkdown: "## Global Style\n- second")
        let secondRuntime = AIContextMemoryRuntime(
            provider: secondProvider,
            eventStore: TypingEventStore(eventsDirectoryURL: eventsDirectory),
            environmentStore: EnvironmentDocumentStore(fileURL: environmentURL),
            batchSize: 1,
            minimumInterval: 10,
            requestGate: ProviderRequestGate(),
            nowProvider: clock.now
        )
        await secondRuntime.processIfNeeded(now: clock.now())
        let requestsBeforeInterval = await secondProvider.requests
        XCTAssertTrue(requestsBeforeInterval.isEmpty)

        clock.advance(by: 11)
        await secondRuntime.processIfNeeded(now: clock.now())
        let requestsAfterInterval = await secondProvider.requests
        XCTAssertEqual(requestsAfterInterval.count, 1)
    }

    func testDirectContextAndRecommendationShareProviderIdentityGate() async throws {
        let directory = makeTemporaryDirectory()
        let provider = DelayedDigestLLMProvider(
            generatedMarkdown: "## Global Style\n- shared",
            delayNanoseconds: 300_000_000
        )
        let gate = ProviderRequestGate()
        let eventStore = TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events"))
        let environmentStore = EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md"))
        let contextRuntime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            requestGate: gate
        )
        let recommendationRuntime = AIRecommendationRuntime(
            provider: provider,
            environmentStore: environmentStore,
            correctionStore: CorrectionInstructionStore(fileURL: directory.appendingPathComponent("CORRECTION.md")),
            debounceMilliseconds: 0,
            requestGate: gate
        )

        let digestTask = Task {
            await contextRuntime.record(makeContextEvent(rawInput: "digest", committedText: "摘要"))
        }
        var digestRequestSeen = false
        let deadline = Date().addingTimeInterval(2)
        while !digestRequestSeen, Date() < deadline {
            digestRequestSeen = !(await provider.requests).isEmpty
            if !digestRequestSeen { try await Task.sleep(nanoseconds: 20_000_000) }
        }
        XCTAssertTrue(digestRequestSeen)

        _ = await recommendationRuntime.recommendation(
            for: AIRecommendationRequest(rawInput: "abc", compositionID: 1)
        )
        let requestCountWhileDigestInFlight = await provider.requests.count
        XCTAssertEqual(requestCountWhileDigestInFlight, 1)
        await digestTask.value
    }

    func testDigestHardTimeoutKeepsGateBusyUntilCancellationResistantProviderFinishes() async throws {
        let directory = makeTemporaryDirectory()
        let provider = CancellationResistantDigestLLMProvider()
        let gate = ProviderRequestGate()
        let eventStore = TypingEventStore(eventsDirectoryURL: directory.appendingPathComponent("events"))
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: EnvironmentDocumentStore(fileURL: directory.appendingPathComponent("ENV.md")),
            batchSize: 1,
            minimumInterval: 600,
            hardTimeoutMilliseconds: 20,
            diagnosticSink: { _ in },
            requestGate: gate
        )

        let startedAt = Date()
        let digest = Task {
            await runtime.record(makeContextEvent(rawInput: "timeout", committedText: "超时"))
        }
        do {
            try await waitUntil { await provider.continuationInstallationCount == 1 }
        } catch {
            digest.cancel()
            _ = await provider.finish(generatedMarkdown: "## Global Style\n- cleanup")
            await digest.value
            throw error
        }
        let installedContinuationCount = await provider.continuationInstallationCount
        guard installedContinuationCount == 1 else {
            digest.cancel()
            _ = await provider.finish(generatedMarkdown: "## Global Style\n- cleanup")
            await digest.value
            return
        }
        await digest.value
        let requestCount = await provider.requestCount
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
        XCTAssertEqual(requestCount, 1)

        var retainedGateLease = false
        do {
            _ = try await gate.execute(providerIdentity: provider.providerName, generation: 0) { 1 }
            XCTFail("timed-out transport must retain the shared gate lease")
        } catch ProviderRequestGateError.busy {
            retainedGateLease = true
        } catch {
            XCTFail("expected busy gate while timed-out transport runs: \(error)")
        }
        XCTAssertTrue(retainedGateLease)

        let finishedStartedTransport = await provider.finish(
            generatedMarkdown: "## Global Style\n- late"
        )
        XCTAssertTrue(finishedStartedTransport)
        let pendingAfterTimeout = try await eventStore.pendingEvents()
        XCTAssertEqual(pendingAfterTimeout.map(\.rawInput), ["timeout"])
        var observedCooldown = false
        let completionDeadline = Date().addingTimeInterval(2)
        while !observedCooldown, Date() < completionDeadline {
            do {
                _ = try await gate.execute(providerIdentity: provider.providerName, generation: 0) { 2 }
                XCTFail("late provider success must not clear the caller timeout cooldown")
                break
            } catch ProviderRequestGateError.busy {
                try await Task.sleep(nanoseconds: 20_000_000)
            } catch ProviderRequestGateError.cooldown {
                observedCooldown = true
            }
        }
        XCTAssertTrue(observedCooldown)

        await gate.invalidate(providerIdentity: provider.providerName, generation: 0)
        let value = try await gate.execute(providerIdentity: provider.providerName, generation: 1) { 3 }
        XCTAssertEqual(value, 3)
    }

    func testDigestTimeoutProtectsClaimThroughCompactionUntilTransportCompletes() async throws {
        let directory = makeTemporaryDirectory()
        let clock = ManualContextClock()
        var policy = TypingEventRetentionPolicy.default
        policy.maximumPendingEventCount = 3
        policy.compactedPendingEventCount = 3
        policy.maximumDigestEventCount = 1
        let eventStore = TypingEventStore(
            eventsDirectoryURL: directory.appendingPathComponent("events"),
            retentionPolicy: policy
        )
        let environmentStore = EnvironmentDocumentStore(
            fileURL: directory.appendingPathComponent("ENV.md")
        )
        let provider = CancellationResistantDigestLLMProvider()
        let gateProbe = ProviderRequestGateTestProbe()
        let gate = ProviderRequestGate(now: clock.now, testProbe: gateProbe)
        let runtimeProbe = AIContextMemoryRuntimeTestProbe(
            pausesAfterGateWaiterInstall: true
        )
        try await eventStore.append(
            makeContextEvent(rawInput: "claimed", committedText: "受保护前缀")
        )
        let claimedSnapshot = try eventStore.pendingDigestSnapshot()
        let runtime = AIContextMemoryRuntime(
            provider: provider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            hardTimeoutMilliseconds: 20,
            diagnosticSink: { _ in },
            requestGate: gate,
            nowProvider: clock.now,
            testProbe: runtimeProbe
        )

        let firstAttempt = Task {
            await runtime.processIfNeeded(now: clock.now())
        }
        do {
            try await waitUntil { await provider.continuationInstallationCount == 1 }
        } catch {
            firstAttempt.cancel()
            _ = await provider.finish(generatedMarkdown: "## Global Style\n- cleanup")
            await firstAttempt.value
            throw error
        }
        let firstContinuationCount = await provider.continuationInstallationCount
        guard firstContinuationCount == 1 else {
            firstAttempt.cancel()
            _ = await provider.finish(generatedMarkdown: "## Global Style\n- cleanup")
            await firstAttempt.value
            return
        }
        await firstAttempt.value
        let protectionAfterTimeout = await runtime.hasActiveDigestClaimProtectionForTesting()
        XCTAssertTrue(protectionAfterTimeout)

        do {
            for index in 0..<3 {
                await runtime.record(
                    makeContextEvent(rawInput: "tail-\(index)", committedText: "尾部\(index)")
                )
            }
            let compactedPending = try await eventStore.pendingEvents()
            XCTAssertEqual(compactedPending.count, 3)
            XCTAssertEqual(compactedPending.first?.rawInput, "claimed")
            XCTAssertFalse(
                eventStore.hasProcessedArchive(
                    prefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
                    byteCount: claimedSnapshot.rawData.count
                )
            )
        } catch {
            _ = await provider.finish(generatedMarkdown: "## Global Style\n- cleanup")
            throw error
        }

        let finishedFirstTransport = await provider.finish(
            generatedMarkdown: "## Global Style\n- late"
        )
        XCTAssertTrue(finishedFirstTransport)
        do {
            try await waitUntil { await runtimeProbe.claimBlockedReevaluationCount == 1 }
        } catch {
            _ = await provider.finish(generatedMarkdown: "## Global Style\n- cleanup")
            throw error
        }
        let reevaluationCount = await runtimeProbe.claimBlockedReevaluationCount
        let requestCountDuringCooldown = await provider.requestCount
        XCTAssertEqual(reevaluationCount, 1)
        XCTAssertEqual(requestCountDuringCooldown, 1)
        try await waitUntil {
            !(await runtime.hasActiveDigestClaimProtectionForTesting())
        }
        let protectionAfterCompletion = await runtime.hasActiveDigestClaimProtectionForTesting()
        guard !protectionAfterCompletion else { return }
        let environmentAfterLateResult = try environmentStore.loadSnapshot().content
        let pendingAfterLateResult = try await eventStore.pendingEvents()
        XCTAssertFalse(environmentAfterLateResult.contains("- late"))
        XCTAssertEqual(pendingAfterLateResult.first?.rawInput, "claimed")
        XCTAssertFalse(
            eventStore.hasProcessedArchive(
                prefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
                byteCount: claimedSnapshot.rawData.count
            )
        )

        clock.advance(by: 61)
        await runtime.cancelGateAvailabilityWaitForTesting()
        let blockerProbe = ContextGateProbe()
        let blocker = Task {
            try await gate.execute(
                providerIdentity: provider.providerName,
                generation: 0
            ) {
                await blockerProbe.markStarted()
                await blockerProbe.waitForRelease()
            }
        }
        do {
            try await waitUntil { await blockerProbe.started }
        } catch {
            blocker.cancel()
            await blockerProbe.release()
            _ = try? await blocker.value
            throw error
        }
        let blockerStarted = await blockerProbe.started
        guard blockerStarted else {
            blocker.cancel()
            await blockerProbe.release()
            _ = try? await blocker.value
            return
        }

        let deadlineDrain = Task {
            await runtime.processIfNeeded(now: clock.now())
        }
        do {
            try await waitUntil { await runtimeProbe.gateWaiterPauseCount == 1 }
        } catch {
            let preflightCountBeforeFailureDrain = gateProbe.preflightCheckCount
            await gate.invalidate(providerIdentity: provider.providerName, generation: 0)
            await runtimeProbe.releaseGateWaiterInstall()
            await blockerProbe.release()
            await deadlineDrain.value
            _ = try? await blocker.value
            try? await waitUntil {
                gateProbe.preflightCheckCount >= preflightCountBeforeFailureDrain + 1
            }
            let drainedPreflightCount = gateProbe.preflightCheckCount
            XCTAssertGreaterThanOrEqual(
                drainedPreflightCount,
                preflightCountBeforeFailureDrain + 1
            )
            guard drainedPreflightCount >= preflightCountBeforeFailureDrain + 1 else {
                throw error
            }
            throw error
        }
        let gateWaiterPauseCount = await runtimeProbe.gateWaiterPauseCount
        guard gateWaiterPauseCount == 1 else {
            let preflightCountBeforeFailureDrain = gateProbe.preflightCheckCount
            await gate.invalidate(providerIdentity: provider.providerName, generation: 0)
            await runtimeProbe.releaseGateWaiterInstall()
            await blockerProbe.release()
            await deadlineDrain.value
            _ = try? await blocker.value
            try? await waitUntil {
                gateProbe.preflightCheckCount >= preflightCountBeforeFailureDrain + 1
            }
            let drainedPreflightCount = gateProbe.preflightCheckCount
            XCTAssertGreaterThanOrEqual(
                drainedPreflightCount,
                preflightCountBeforeFailureDrain + 1
            )
            guard drainedPreflightCount >= preflightCountBeforeFailureDrain + 1 else {
                return
            }
            return
        }
        XCTAssertEqual(gateWaiterPauseCount, 1)

        let preflightCountBeforeDrain = gateProbe.preflightCheckCount
        await gate.invalidate(providerIdentity: provider.providerName, generation: 0)
        await runtimeProbe.releaseGateWaiterInstall()
        await deadlineDrain.value
        do {
            try await waitUntil {
                gateProbe.preflightCheckCount >= preflightCountBeforeDrain + 1
            }
        } catch {
            await blockerProbe.release()
            _ = try? await blocker.value
            throw error
        }
        let drainedPreflightCount = gateProbe.preflightCheckCount
        guard drainedPreflightCount >= preflightCountBeforeDrain + 1 else {
            await blockerProbe.release()
            _ = try? await blocker.value
            return
        }

        await blockerProbe.release()
        var blockerFinishedStale = false
        do {
            try await blocker.value
            XCTFail("invalidated deadline blocker must finish stale")
        } catch ProviderRequestGateError.staleGeneration {
            blockerFinishedStale = true
        } catch {
            XCTFail("unexpected deadline blocker error: \(error)")
        }
        XCTAssertTrue(blockerFinishedStale)
        guard blockerFinishedStale else { return }
        let requestCountAfterDeadlineDrain = await provider.requestCount
        XCTAssertEqual(requestCountAfterDeadlineDrain, 1)
        guard requestCountAfterDeadlineDrain == 1 else {
            let completedResponseCountBeforeCleanup = await provider.completedResponseCount
            let finishedCleanupTransport = await provider.finish(
                generatedMarkdown: "## Global Style\n- cleanup"
            )
            if finishedCleanupTransport || requestCountAfterDeadlineDrain > 1 {
                let expectedCompletedResponseCount = max(
                    requestCountAfterDeadlineDrain,
                    completedResponseCountBeforeCleanup + (finishedCleanupTransport ? 1 : 0)
                )
                try? await waitUntil {
                    await provider.completedResponseCount >= expectedCompletedResponseCount
                }
                let completedResponseCountAfterCleanup = await provider.completedResponseCount
                XCTAssertGreaterThanOrEqual(
                    completedResponseCountAfterCleanup,
                    expectedCompletedResponseCount
                )
            }
            return
        }

        let retryProvider = CancellationResistantDigestLLMProvider()
        await retryProvider.queueResponse(generatedMarkdown: "## Global Style\n- retry")
        let retryGate = ProviderRequestGate(now: clock.now)
        let retryRuntime = AIContextMemoryRuntime(
            provider: retryProvider,
            eventStore: eventStore,
            environmentStore: environmentStore,
            batchSize: 1,
            minimumInterval: 600,
            hardTimeoutMilliseconds: 5_000,
            diagnosticSink: { _ in },
            requestGate: retryGate,
            nowProvider: clock.now
        )
        let retry = Task {
            await retryRuntime.processIfNeeded(now: clock.now())
        }
        do {
            try await waitUntil { await retryProvider.completedResponseCount == 1 }
        } catch {
            retry.cancel()
            _ = await retryProvider.finish(generatedMarkdown: "## Global Style\n- cleanup")
            await retry.value
            throw error
        }
        let retryResponseCompletionCount = await retryProvider.completedResponseCount
        guard retryResponseCompletionCount == 1 else {
            retry.cancel()
            _ = await retryProvider.finish(generatedMarkdown: "## Global Style\n- cleanup")
            await retry.value
            return
        }
        XCTAssertEqual(retryResponseCompletionCount, 1)
        await retry.value

        let originalProviderRequestCountAfterRetry = await provider.requestCount
        XCTAssertEqual(originalProviderRequestCountAfterRetry, 1)
        let retrySchedule = try XCTUnwrap(environmentStore.loadDigestScheduleState())
        XCTAssertEqual(retrySchedule.lastSuccessfulDigestAt, clock.now())
        XCTAssertEqual(retrySchedule.pendingEventCount, 2)
        let finalEnvironment = try environmentStore.loadSnapshot().content
        let finalPending = try await eventStore.pendingEvents()
        XCTAssertTrue(finalEnvironment.contains("- retry"))
        XCTAssertFalse(finalPending.contains { $0.rawInput == "claimed" })
        XCTAssertTrue(
            eventStore.hasProcessedArchive(
                prefixSHA256: AIDocumentSnapshot.hash(claimedSnapshot.rawContent),
                byteCount: claimedSnapshot.rawData.count
            )
        )
    }
}

private actor ControlledContextDeadlineSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var suspensionCount = 0

    func suspend(nanoseconds _: UInt64) async {
        suspensionCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func releaseNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

private final class ManualContextClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }
}

private actor ContextGateProbe {
    private(set) var started = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func markStarted() {
        started = true
    }

    func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private func makeContextEvent(
    timestamp: Date = Date(),
    rawInput: String,
    committedText: String
) -> AITypingEvent {
    AITypingEvent(
        timestamp: timestamp,
        rawInput: rawInput,
        committedText: committedText,
        commitKind: .traditional,
        candidateSource: "traditional"
    )
}

private func rawDataSHA256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
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

private actor RateLimitedDigestLLMProvider: LLMProvider {
    nonisolated let providerName = "rate-limited-digest"
    private let retryAfterSeconds: TimeInterval
    private var recordedRequests: [LLMRequest] = []

    init(retryAfterSeconds: TimeInterval) {
        self.retryAfterSeconds = retryAfterSeconds
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        recordedRequests.append(request)
        throw ProviderRateLimitError(
            retryAfterSeconds: retryAfterSeconds,
            bodyByteCount: 128
        )
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

private actor CancellationResistantDigestLLMProvider: LLMProvider {
    nonisolated let providerName = "cancellation-resistant-digest"
    private var count = 0
    private var completedCount = 0
    private var installedContinuationCount = 0
    private var continuation: CheckedContinuation<LLMResponse, Never>?
    private var queuedResponses: [LLMResponse] = []

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        count += 1
        let response: LLMResponse
        if !queuedResponses.isEmpty {
            response = queuedResponses.removeFirst()
        } else {
            response = await withCheckedContinuation { continuation in
                self.continuation = continuation
                installedContinuationCount += 1
            }
        }
        completedCount += 1
        return response
    }

    func queueResponse(generatedMarkdown: String) {
        queuedResponses.append(
            LLMResponse(candidates: [
                LLMCandidate(text: generatedMarkdown, confidence: 0.9)
            ])
        )
    }

    @discardableResult
    func finish(generatedMarkdown: String) -> Bool {
        let response = LLMResponse(candidates: [
            LLMCandidate(text: generatedMarkdown, confidence: 0.9)
        ])
        guard let continuation else {
            queueResponse(generatedMarkdown: generatedMarkdown)
            return false
        }
        self.continuation = nil
        continuation.resume(returning: response)
        return true
    }

    var requestCount: Int {
        count
    }

    var continuationInstallationCount: Int {
        installedContinuationCount
    }

    var completedResponseCount: Int {
        completedCount
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
            minimumInterval: 600,
            requestGate: ProviderRequestGate()
        )
    }

    var wasCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return called
    }
}

private final class ContextMemoryDiagnosticProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedLines: [String] = []

    func record(_ fields: [InputDebugDiagnostics.Field]) {
        let line = InputDebugDiagnostics.formatLine(category: .ai, fields: fields)
        lock.lock()
        recordedLines.append(line)
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLines
    }

    func stageCount(_ stage: String) -> Int {
        lines.filter { $0.contains("stage=\(stage)") }.count
    }
}

private final class PendingAttributesErrorFileManager: FileManager, @unchecked Sendable {
    private let pendingPath: String
    private let error: NSError

    init(pendingURL: URL, error: NSError) {
        self.pendingPath = pendingURL.path
        self.error = error
        super.init()
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if path == pendingPath { throw error }
        return try super.attributesOfItem(atPath: path)
    }
}

private struct ArchivedDigestClaimRecoveryFixture {
    let eventStore: TypingEventStore
    let environmentStore: EnvironmentDocumentStore
    let environmentURL: URL
    let claim: EnvironmentDigestClaim
}

private func makeArchivedDigestClaimRecoveryFixture(
    directory: URL,
    timestamp: Date,
    generated: String
) async throws -> ArchivedDigestClaimRecoveryFixture {
    let eventStore = TypingEventStore(
        eventsDirectoryURL: directory.appendingPathComponent("events")
    )
    try await eventStore.append(
        makeContextEvent(
            timestamp: timestamp,
            rawInput: "claimed-recovery",
            committedText: "已归档"
        )
    )
    let snapshot = try eventStore.pendingDigestSnapshot()
    let environmentURL = directory.appendingPathComponent("ENV.md")
    let environmentStore = EnvironmentDocumentStore(fileURL: environmentURL)
    _ = try environmentStore.replaceGeneratedSection(with: generated)
    let claim = EnvironmentDigestClaim(
        claimedPrefixSHA256: AIDocumentSnapshot.hash(snapshot.rawContent),
        claimedPrefixByteCount: snapshot.rawData.count,
        claimedEventCount: snapshot.claimedEventCount,
        generatedSHA256: AIDocumentSnapshot.hash(generated),
        providerGeneration: 0
    )
    try environmentStore.saveDigestClaim(claim)
    _ = try eventStore.commitPendingEvents(matching: snapshot, beforeArchive: {})
    return ArchivedDigestClaimRecoveryFixture(
        eventStore: eventStore,
        environmentStore: environmentStore,
        environmentURL: environmentURL,
        claim: claim
    )
}

private func digestArchiveReceipt(
    for claim: EnvironmentDigestClaim,
    successfulDigestAt: Date
) -> EnvironmentDigestArchiveReceipt {
    EnvironmentDigestArchiveReceipt(
        claimedPrefixSHA256: claim.claimedPrefixSHA256,
        claimedPrefixByteCount: claim.claimedPrefixByteCount,
        claimedEventCount: claim.claimedEventCount,
        generatedSHA256: claim.generatedSHA256,
        archivedByteCount: claim.claimedPrefixByteCount,
        successfulDigestAt: successfulDigestAt
    )
}

private func writeLegacyDigestArchiveReceipt(
    for claim: EnvironmentDigestClaim,
    in directory: URL
) throws {
    let receipt: [String: Any] = [
        "claimedPrefixSHA256": claim.claimedPrefixSHA256,
        "claimedPrefixByteCount": claim.claimedPrefixByteCount,
        "claimedEventCount": claim.claimedEventCount,
        "generatedSHA256": claim.generatedSHA256,
        "archivedByteCount": claim.claimedPrefixByteCount
    ]
    let receiptURL = directory.appendingPathComponent("ENV.digest-archive-receipt.json")
    try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        .write(to: receiptURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: receiptURL.path
    )
}

private func writeLegacyDigestSchedule(
    lastSuccessfulDigestAt: Date,
    pendingEventCount: Int,
    in directory: URL
) throws {
    let schedule: [String: Any] = [
        "lastSuccessfulDigestAt": lastSuccessfulDigestAt.timeIntervalSinceReferenceDate,
        "pendingEventCount": pendingEventCount
    ]
    let scheduleURL = directory.appendingPathComponent("ENV.digest-schedule.json")
    try JSONSerialization.data(withJSONObject: schedule, options: [.sortedKeys])
        .write(to: scheduleURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: scheduleURL.path
    )
}

private func seedProcessedRetentionArchives(
    at processedDirectory: URL,
    now: Date,
    byteCount: Int = 100
) throws -> (expired: URL, oldestRecent: URL, newestRecent: URL) {
    try FileManager.default.createDirectory(
        at: processedDirectory,
        withIntermediateDirectories: true
    )
    let archives = [
        (
            processedDirectory.appendingPathComponent("typing-events-seed-expired.jsonl"),
            now.addingTimeInterval(-8 * 24 * 60 * 60)
        ),
        (
            processedDirectory.appendingPathComponent("typing-events-seed-oldest.jsonl"),
            now.addingTimeInterval(-2)
        ),
        (
            processedDirectory.appendingPathComponent("typing-events-seed-newest.jsonl"),
            now.addingTimeInterval(-1)
        )
    ]
    for (url, modificationDate) in archives {
        try Data(repeating: 0x61, count: byteCount).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: url.path
        )
    }
    return (
        expired: archives[0].0,
        oldestRecent: archives[1].0,
        newestRecent: archives[2].0
    )
}

private func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("KnowTypeAIContextTests-\(UUID().uuidString)", isDirectory: true)
}
