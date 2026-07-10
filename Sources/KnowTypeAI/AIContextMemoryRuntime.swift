import Foundation
import KnowTypeCore
import KnowTypeProviders

public enum TypingEventStoreError: Error, Equatable {
    case pendingContentChanged
}

private let typingEventFileLock = NSLock()

private func withTypingEventFileLock<T>(_ body: () throws -> T) rethrows -> T {
    typingEventFileLock.lock()
    defer { typingEventFileLock.unlock() }
    return try body()
}

public final class TypingEventStore: @unchecked Sendable {
    private let eventsFileURL: URL
    private let processedDirectoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        eventsDirectoryURL: URL = AIUserDirectory.defaultDirectory().eventsDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.eventsFileURL = eventsDirectoryURL.appendingPathComponent("typing-events.jsonl")
        self.processedDirectoryURL = eventsDirectoryURL.appendingPathComponent("processed", isDirectory: true)
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ event: AITypingEvent) async throws {
        try withTypingEventFileLock {
            try fileManager.createDirectory(
                at: eventsFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(event)
            var line = data
            line.append(0x0A)
            if fileManager.fileExists(atPath: eventsFileURL.path) {
                let handle = try FileHandle(forWritingTo: eventsFileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: eventsFileURL, options: .atomic)
            }
        }
    }

    public func pendingEvents() async throws -> [AITypingEvent] {
        try pendingSnapshotSynchronously().events
    }

    public func pendingRawContent() async throws -> String {
        try pendingSnapshotSynchronously().rawContent
    }

    public func pendingSnapshot() async throws -> (rawContent: String, events: [AITypingEvent]) {
        try pendingSnapshotSynchronously()
    }

    private func pendingSnapshotSynchronously() throws -> (rawContent: String, events: [AITypingEvent]) {
        try withTypingEventFileLock {
            guard fileManager.fileExists(atPath: eventsFileURL.path) else {
                return ("", [])
            }
            let content = try String(contentsOf: eventsFileURL, encoding: .utf8)
            let events = content
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> AITypingEvent? in
                    guard let data = String(line).data(using: .utf8) else {
                        return nil
                    }
                    return try? decoder.decode(AITypingEvent.self, from: data)
                }
            return (content, events)
        }
    }

    public func archivePendingEvents() async throws {
        let rawContent = try pendingSnapshotSynchronously().rawContent
        try archivePendingEventsSynchronously(matchingRawContent: rawContent)
    }

    public func archivePendingEvents(matchingRawContent rawContent: String) async throws {
        try archivePendingEventsSynchronously(matchingRawContent: rawContent)
    }

    public func commitPendingEvents(
        matchingRawContent rawContent: String,
        beforeArchive: @Sendable () throws -> Void
    ) throws {
        try archivePendingEventsSynchronously(
            matchingRawContent: rawContent,
            beforeArchive: beforeArchive
        )
    }

    private func archivePendingEventsSynchronously(
        matchingRawContent rawContent: String,
        beforeArchive: @Sendable () throws -> Void = {}
    ) throws {
        try withTypingEventFileLock {
            guard !rawContent.isEmpty,
                  fileManager.fileExists(atPath: eventsFileURL.path) else {
                return
            }
            let currentContent = try String(contentsOf: eventsFileURL, encoding: .utf8)
            guard currentContent.hasPrefix(rawContent) else {
                throw TypingEventStoreError.pendingContentChanged
            }
            try beforeArchive()
            try fileManager.createDirectory(at: processedDirectoryURL, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            let filename = "typing-events-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString).jsonl"
            let destination = processedDirectoryURL.appendingPathComponent(filename)
            try rawContent.write(to: destination, atomically: true, encoding: .utf8)

            let remainingContent = String(currentContent.dropFirst(rawContent.count))
            if remainingContent.isEmpty {
                try fileManager.removeItem(at: eventsFileURL)
            } else {
                try remainingContent.write(to: eventsFileURL, atomically: true, encoding: .utf8)
            }
        }
    }
}

public actor LazyDefaultAIContextMemoryRuntime: AIContextEventRecording {
    private let providerLoader: @Sendable () -> (any LLMProvider)?
    private let runtimeFactory: @Sendable (any LLMProvider) -> AIContextMemoryRuntime
    private var runtime: AIContextMemoryRuntime?

    public init(
        providerLoader: @escaping @Sendable () -> (any LLMProvider)? = {
            ProviderRuntimeLoader.loadDefaultProvider(createProfileDirectory: false)
        },
        runtimeFactory: @escaping @Sendable (any LLMProvider) -> AIContextMemoryRuntime = {
            AIContextMemoryRuntime(provider: $0)
        }
    ) {
        self.providerLoader = providerLoader
        self.runtimeFactory = runtimeFactory
    }

    public func record(_ event: AITypingEvent) async {
        if let runtime {
            await runtime.record(event)
            return
        }
        guard let provider = providerLoader() else {
            return
        }
        let runtime = runtimeFactory(provider)
        self.runtime = runtime
        await runtime.record(event)
    }
}

public actor AIContextMemoryRuntime: AIContextEventRecording {
    private let provider: (any LLMProvider)?
    private let providerRegistry: ProviderRuntimeRegistry?
    private let eventStore: TypingEventStore
    private let environmentStore: EnvironmentDocumentStore
    private let batchSize: Int
    private let minimumInterval: TimeInterval
    private var lastDigestAt: Date?
    private var lastDigestFailureAt: Date?
    private var digestInFlight = false
    private var providerGeneration: UInt64?

    public init(
        provider: (any LLMProvider)?,
        eventStore: TypingEventStore = TypingEventStore(),
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        batchSize: Int = 50,
        minimumInterval: TimeInterval = 600
    ) {
        self.provider = provider
        self.providerRegistry = nil
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = max(1, minimumInterval)
    }

    public init(
        providerRegistry: ProviderRuntimeRegistry,
        eventStore: TypingEventStore = TypingEventStore(),
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        batchSize: Int = 50,
        minimumInterval: TimeInterval = 600
    ) {
        self.provider = nil
        self.providerRegistry = providerRegistry
        self.eventStore = eventStore
        self.environmentStore = environmentStore
        self.batchSize = max(1, batchSize)
        self.minimumInterval = max(1, minimumInterval)
    }

    public func record(_ event: AITypingEvent) async {
        do {
            try await eventStore.append(sanitized(event))
            await processIfNeeded()
        } catch {
            return
        }
    }

    public func processIfNeeded(now: Date = Date()) async {
        guard !digestInFlight,
              provider != nil || providerRegistry != nil else {
            return
        }
        digestInFlight = true
        defer { digestInFlight = false }

        let snapshot: (rawContent: String, events: [AITypingEvent])
        do {
            snapshot = try await eventStore.pendingSnapshot()
        } catch {
            return
        }
        let events = snapshot.events
        guard !events.isEmpty else {
            return
        }
        if lastDigestAt == nil, events.count < batchSize {
            lastDigestAt = now
            return
        }
        let intervalElapsed = lastDigestAt.map { now.timeIntervalSince($0) >= minimumInterval } ?? false
        guard events.count >= batchSize || intervalElapsed else {
            return
        }
        if events.allSatisfy(Self.isProtectedOnlyEvent) {
            do {
                try await eventStore.archivePendingEvents(matchingRawContent: snapshot.rawContent)
                lastDigestAt = now
            } catch {
                return
            }
            return
        }
        if let providerRegistry,
           let providerGeneration {
            let registryGeneration = await providerRegistry.currentGeneration()
            if registryGeneration > 0, registryGeneration != providerGeneration {
                resetProviderRuntimeState()
            }
        }
        if let lastDigestFailureAt,
           now.timeIntervalSince(lastDigestFailureAt) < minimumInterval {
            return
        }

        do {
            let rawEvents = snapshot.rawContent
            guard !rawEvents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                lastDigestAt = now
                return
            }
            let currentEnvironment = try environmentStore.loadSnapshot()
            let lease: ProviderRuntimeLease?
            let activeProvider: (any LLMProvider)?
            if let providerRegistry {
                let loadedLease = await providerRegistry.leaseForEligibleDispatch()
                if providerGeneration != loadedLease.generation {
                    resetProviderRuntimeState()
                    providerGeneration = loadedLease.generation
                }
                lease = loadedLease
                activeProvider = loadedLease.provider
            } else {
                lease = nil
                activeProvider = provider
            }
            guard let activeProvider else {
                return
            }
            let request = LLMRequest(
                task: .contextDigest,
                rawInput: rawEvents,
                locale: .mixed,
                appContext: "KnowTypeContextMemory",
                maxCandidates: 1,
                contextDocuments: [
                    "ENV.md": currentEnvironment.content
                ]
            )
            let response: LLMResponse
            if let providerRegistry, let lease {
                response = try await providerRegistry.perform(using: lease) { provider in
                    try await provider.complete(request)
                }
            } else {
                response = try await activeProvider.complete(request)
            }
            guard let generated = Self.generatedDigestText(from: response) else {
                lastDigestFailureAt = now
                return
            }
            let eventStore = self.eventStore
            let environmentStore = self.environmentStore
            let persist: @Sendable () throws -> Void = {
                try eventStore.commitPendingEvents(matchingRawContent: rawEvents) {
                    _ = try environmentStore.replaceGeneratedSection(with: generated)
                }
            }
            if let providerRegistry, let lease {
                try await providerRegistry.commitIfCurrent(using: lease, operation: persist)
            } else {
                try persist()
            }
            lastDigestAt = now
            lastDigestFailureAt = nil
        } catch ProviderRuntimeRegistryError.staleGeneration {
            resetProviderRuntimeState()
            return
        } catch {
            lastDigestFailureAt = now
            return
        }
    }

    private func resetProviderRuntimeState() {
        lastDigestAt = nil
        lastDigestFailureAt = nil
        providerGeneration = nil
    }

    private static func isProtectedOnlyEvent(_ event: AITypingEvent) -> Bool {
        guard event.candidateSource == "protected" else {
            return false
        }
        let protectedValues = [event.rawInput, event.committedText].compactMap { $0 }
        return !protectedValues.isEmpty
            && protectedValues.allSatisfy { $0.hasPrefix("protected:") }
    }

    private static func generatedDigestText(from response: LLMResponse) -> String? {
        let parts = response.candidates
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: "\n")
    }

    private func sanitized(_ event: AITypingEvent) -> AITypingEvent {
        var event = event
        if event.commitKind == .externalDelete,
           event.rawInput == nil,
           event.committedText == nil,
           TextProtection.requiresNoCorrection("knowtype", appBundleID: event.appBundleID) {
            event.rawInput = "protected:delete"
            event.committedText = "protected:delete"
            event.candidateSource = "protected"
            return event
        }
        if let rawInput = event.rawInput,
           TextProtection.requiresNoCorrection(rawInput, appBundleID: event.appBundleID) {
            event.rawInput = protectedLabel(for: rawInput)
            event.committedText = event.rawInput
            event.candidateSource = "protected"
        }
        if let committedText = event.committedText,
           TextProtection.requiresNoCorrection(committedText, appBundleID: event.appBundleID) {
            event.committedText = protectedLabel(for: committedText)
            event.candidateSource = "protected"
        }
        return event
    }

    private func protectedLabel(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return "protected:url"
        }
        if trimmed.contains("/") {
            return "protected:path"
        }
        if trimmed.contains("@") {
            return "protected:email"
        }
        return "protected:command"
    }
}
