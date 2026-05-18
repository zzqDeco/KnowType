import Foundation
import KnowTypeCore

public enum TypingEventStoreError: Error, Equatable {
    case pendingContentChanged
}

private let typingEventFileLock = NSLock()

private func withTypingEventFileLock<T>(_ body: () throws -> T) rethrows -> T {
    typingEventFileLock.lock()
    defer { typingEventFileLock.unlock() }
    return try body()
}

public actor TypingEventStore {
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

    public func append(_ event: AITypingEvent) throws {
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

    public func pendingEvents() throws -> [AITypingEvent] {
        try pendingSnapshot().events
    }

    public func pendingRawContent() throws -> String {
        try pendingSnapshot().rawContent
    }

    public func pendingSnapshot() throws -> (rawContent: String, events: [AITypingEvent]) {
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

    public func archivePendingEvents() throws {
        try archivePendingEvents(matchingRawContent: pendingRawContent())
    }

    public func archivePendingEvents(matchingRawContent rawContent: String) throws {
        try withTypingEventFileLock {
            guard !rawContent.isEmpty,
                  fileManager.fileExists(atPath: eventsFileURL.path) else {
                return
            }
            let currentContent = try String(contentsOf: eventsFileURL, encoding: .utf8)
            guard currentContent.hasPrefix(rawContent) else {
                throw TypingEventStoreError.pendingContentChanged
            }
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

public actor AIContextMemoryRuntime: AIContextEventRecording {
    private let provider: (any LLMProvider)?
    private let eventStore: TypingEventStore
    private let environmentStore: EnvironmentDocumentStore
    private let batchSize: Int
    private let minimumInterval: TimeInterval
    private var lastDigestAt: Date?
    private var lastDigestFailureAt: Date?
    private var digestInFlight = false

    public init(
        provider: (any LLMProvider)?,
        eventStore: TypingEventStore = TypingEventStore(),
        environmentStore: EnvironmentDocumentStore = EnvironmentDocumentStore(),
        batchSize: Int = 50,
        minimumInterval: TimeInterval = 600
    ) {
        self.provider = provider
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
              let provider else {
            return
        }
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
        if let lastDigestFailureAt,
           now.timeIntervalSince(lastDigestFailureAt) < minimumInterval {
            return
        }

        digestInFlight = true
        defer { digestInFlight = false }
        do {
            let rawEvents = snapshot.rawContent
            guard !rawEvents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                lastDigestAt = now
                return
            }
            let currentEnvironment = try environmentStore.loadSnapshot()
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
            let response = try await provider.complete(request)
            guard let generated = response.candidates.first?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !generated.isEmpty else {
                return
            }
            _ = try environmentStore.replaceGeneratedSection(with: generated)
            try await eventStore.archivePendingEvents(matchingRawContent: rawEvents)
            lastDigestAt = now
            lastDigestFailureAt = nil
        } catch {
            lastDigestFailureAt = now
            return
        }
    }

    private static func isProtectedOnlyEvent(_ event: AITypingEvent) -> Bool {
        guard event.candidateSource == "protected" else {
            return false
        }
        let protectedValues = [event.rawInput, event.committedText].compactMap { $0 }
        return !protectedValues.isEmpty
            && protectedValues.allSatisfy { $0.hasPrefix("protected:") }
    }

    private func sanitized(_ event: AITypingEvent) -> AITypingEvent {
        var event = event
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
