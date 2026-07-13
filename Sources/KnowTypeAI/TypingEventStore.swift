import Foundation

public enum TypingEventStoreError: Error, Equatable {
    case pendingContentChanged
}

struct TypingEventInventory: Sendable, Equatable {
    var eventCount: Int
    var byteCount: Int
    var protectedEventCount: Int

    static let empty = TypingEventInventory(eventCount: 0, byteCount: 0, protectedEventCount: 0)

    var unprotectedEventCount: Int {
        max(0, eventCount - protectedEventCount)
    }

    var isProtectedOnly: Bool {
        eventCount > 0 && protectedEventCount == eventCount
    }
}

struct TypingEventSnapshot: Sendable, Equatable {
    var rawData: Data
    var requestData: Data
    var events: [AITypingEvent]
    var claimedEventCount: Int

    var rawContent: String {
        String(decoding: rawData, as: UTF8.self)
    }

    var byteCount: Int {
        rawData.count
    }

    var requestContent: String {
        String(decoding: requestData, as: UTF8.self)
    }
}

struct TypingEventRetentionPolicy: Sendable, Equatable {
    var maximumPendingEventCount: Int = 500
    var maximumPendingByteCount: Int = 1_048_576
    var compactedPendingEventCount: Int = 450
    var compactedPendingByteCount: Int = 786_432
    var maximumDigestEventCount: Int = 50
    var maximumDigestByteCount: Int = 262_144
    var maximumTextScalarCount: Int = 2_048
    var processedMaximumAge: TimeInterval = 7 * 24 * 60 * 60
    var processedMaximumFileCount: Int = 100
    var processedMaximumByteCount: Int = 10 * 1_048_576

    static let `default` = TypingEventRetentionPolicy()
}

struct TypingEventAppendResult: Sendable, Equatable {
    var inventory: TypingEventInventory
    var truncatedScalarCount: Int
    var droppedEventCount: Int
    var droppedByteCount: Int
}

struct TypingEventArchiveResult: Sendable, Equatable {
    var deletedFileCount: Int
    var deletedByteCount: Int

    static let empty = TypingEventArchiveResult(deletedFileCount: 0, deletedByteCount: 0)
}

final class TypingEventStoreTestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var inventoryScans = 0
    private var digestSnapshotDecodes = 0
    private var atomicRewrites = 0
    private var failedArchiveDeletionsRemaining = 0

    var inventoryScanCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return inventoryScans
    }

    var digestSnapshotDecodeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return digestSnapshotDecodes
    }

    var atomicRewriteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return atomicRewrites
    }

    func failNextArchiveDeletions(_ count: Int) {
        lock.lock()
        failedArchiveDeletionsRemaining = max(0, count)
        lock.unlock()
    }

    fileprivate func recordInventoryScan() {
        lock.lock()
        inventoryScans += 1
        lock.unlock()
    }

    fileprivate func recordDigestSnapshotDecode() {
        lock.lock()
        digestSnapshotDecodes += 1
        lock.unlock()
    }

    fileprivate func recordAtomicRewrite() {
        lock.lock()
        atomicRewrites += 1
        lock.unlock()
    }

    fileprivate func shouldFailArchiveDeletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failedArchiveDeletionsRemaining > 0 else {
            return false
        }
        failedArchiveDeletionsRemaining -= 1
        return true
    }
}

private struct TypingEventFileMetadata: Sendable, Equatable {
    var byteCount: Int
    var modificationDate: Date?
    var fileNumber: UInt64?
}

private struct TypingEventInventoryCacheEntry: Sendable {
    var metadata: TypingEventFileMetadata?
    var inventory: TypingEventInventory
}

private let typingEventFileLock = NSLock()
private nonisolated(unsafe) var typingEventInventoryCache: [String: TypingEventInventoryCacheEntry] = [:]

private func withTypingEventFileLock<T>(_ body: () throws -> T) rethrows -> T {
    typingEventFileLock.lock()
    defer { typingEventFileLock.unlock() }
    return try body()
}

public final class TypingEventStore: @unchecked Sendable {
    private let eventsFileURL: URL
    private let processedDirectoryURL: URL
    private let fileManager: FileManager
    private let retentionPolicy: TypingEventRetentionPolicy
    private let testProbe: TypingEventStoreTestProbe?
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        eventsDirectoryURL: URL = AIUserDirectory.defaultDirectory().eventsDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.eventsFileURL = eventsDirectoryURL.appendingPathComponent("typing-events.jsonl")
        self.processedDirectoryURL = eventsDirectoryURL.appendingPathComponent("processed", isDirectory: true)
        self.fileManager = fileManager
        self.retentionPolicy = .default
        self.testProbe = nil
        self.now = Date.init
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    init(
        eventsDirectoryURL: URL,
        fileManager: FileManager = .default,
        retentionPolicy: TypingEventRetentionPolicy,
        testProbe: TypingEventStoreTestProbe? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.eventsFileURL = eventsDirectoryURL.appendingPathComponent("typing-events.jsonl")
        self.processedDirectoryURL = eventsDirectoryURL.appendingPathComponent("processed", isDirectory: true)
        self.fileManager = fileManager
        self.retentionPolicy = retentionPolicy
        self.testProbe = testProbe
        self.now = now
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ event: AITypingEvent) async throws {
        _ = try appendBounded(event)
    }

    func appendBounded(_ event: AITypingEvent) throws -> TypingEventAppendResult {
        try withTypingEventFileLock {
            var boundedEvent = event
            let rawResult = boundedText(event.rawInput)
            let committedResult = boundedText(event.committedText)
            boundedEvent.rawInput = rawResult.text
            boundedEvent.committedText = committedResult.text

            try fileManager.createDirectory(
                at: eventsFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let existingInventory = try inventorySynchronously()
            var line = try encoder.encode(boundedEvent)
            line.append(0x0A)
            if fileManager.fileExists(atPath: eventsFileURL.path) {
                let handle = try FileHandle(forWritingTo: eventsFileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: eventsFileURL, options: .atomic)
            }

            var inventory = existingInventory
            inventory.eventCount += 1
            inventory.byteCount += line.count
            if Self.isProtectedOnlyEvent(boundedEvent) {
                inventory.protectedEventCount += 1
            }
            cacheInventory(inventory)

            var droppedEventCount = 0
            var droppedByteCount = 0
            if inventory.eventCount > retentionPolicy.maximumPendingEventCount
                || inventory.byteCount > retentionPolicy.maximumPendingByteCount {
                let compaction = try compactPendingSynchronously()
                inventory = compaction.inventory
                droppedEventCount = compaction.droppedEventCount
                droppedByteCount = compaction.droppedByteCount
            }

            return TypingEventAppendResult(
                inventory: inventory,
                truncatedScalarCount: rawResult.removedScalarCount + committedResult.removedScalarCount,
                droppedEventCount: droppedEventCount,
                droppedByteCount: droppedByteCount
            )
        }
    }

    func inventory() throws -> TypingEventInventory {
        try withTypingEventFileLock {
            try inventorySynchronously()
        }
    }

    public func pendingEvents() async throws -> [AITypingEvent] {
        try withTypingEventFileLock {
            try fullSnapshotSynchronously().events
        }
    }

    public func pendingRawContent() async throws -> String {
        try withTypingEventFileLock {
            try fullSnapshotSynchronously().rawContent
        }
    }

    public func pendingSnapshot() async throws -> (rawContent: String, events: [AITypingEvent]) {
        try withTypingEventFileLock {
            let snapshot = try fullSnapshotSynchronously()
            return (snapshot.rawContent, snapshot.events)
        }
    }

    func pendingDigestSnapshot() throws -> TypingEventSnapshot {
        try withTypingEventFileLock {
            testProbe?.recordDigestSnapshotDecode()
            guard fileManager.fileExists(atPath: eventsFileURL.path) else {
                return TypingEventSnapshot(
                    rawData: Data(),
                    requestData: Data(),
                    events: [],
                    claimedEventCount: 0
                )
            }
            let rawData = try readDigestPrefixSynchronously()
            return decodeSnapshot(rawData)
        }
    }

    func pendingFullSnapshot() throws -> TypingEventSnapshot {
        try withTypingEventFileLock {
            try fullSnapshotSynchronously()
        }
    }

    public func archivePendingEvents() async throws {
        try withTypingEventFileLock {
            let rawData = try fullSnapshotSynchronously().rawData
            _ = try archivePendingEventsSynchronously(
                matchingRawData: rawData,
                pruneProcessedArchives: false
            )
        }
    }

    public func archivePendingEvents(matchingRawContent rawContent: String) async throws {
        try withTypingEventFileLock {
            _ = try archivePendingEventsSynchronously(
                matchingRawData: Data(rawContent.utf8),
                pruneProcessedArchives: false
            )
        }
    }

    public func commitPendingEvents(
        matchingRawContent rawContent: String,
        beforeArchive: @Sendable () throws -> Void
    ) throws {
        try withTypingEventFileLock {
            _ = try archivePendingEventsSynchronously(
                matchingRawData: Data(rawContent.utf8),
                pruneProcessedArchives: true,
                beforeArchive: beforeArchive
            )
        }
    }

    func commitPendingEvents(
        matching snapshot: TypingEventSnapshot,
        beforeArchive: @Sendable () throws -> Void
    ) throws -> TypingEventArchiveResult {
        try withTypingEventFileLock {
            try archivePendingEventsSynchronously(
                matchingRawData: snapshot.rawData,
                pruneProcessedArchives: true,
                beforeArchive: beforeArchive
            )
        }
    }

    func archivePendingEvents(matching snapshot: TypingEventSnapshot) throws {
        try withTypingEventFileLock {
            _ = try archivePendingEventsSynchronously(
                matchingRawData: snapshot.rawData,
                pruneProcessedArchives: false
            )
        }
    }

    static func resetInventoryCacheForTesting(eventsDirectoryURL: URL) {
        let eventsFileURL = eventsDirectoryURL.appendingPathComponent("typing-events.jsonl")
        _ = withTypingEventFileLock {
            typingEventInventoryCache.removeValue(forKey: normalizedPath(for: eventsFileURL))
        }
    }

    private func boundedText(_ text: String?) -> (text: String?, removedScalarCount: Int) {
        guard let text else {
            return (nil, 0)
        }
        let scalars = text.unicodeScalars
        guard scalars.count > retentionPolicy.maximumTextScalarCount else {
            return (text, 0)
        }
        let prefix = String(String.UnicodeScalarView(scalars.prefix(retentionPolicy.maximumTextScalarCount)))
        return (prefix, scalars.count - retentionPolicy.maximumTextScalarCount)
    }

    private func inventorySynchronously() throws -> TypingEventInventory {
        let key = Self.normalizedPath(for: eventsFileURL)
        let metadata = fileMetadata()
        if let cached = typingEventInventoryCache[key], cached.metadata == metadata {
            return cached.inventory
        }
        let data: Data
        if fileManager.fileExists(atPath: eventsFileURL.path) {
            data = try Data(contentsOf: eventsFileURL)
        } else {
            data = Data()
        }
        let inventory = inventory(for: data)
        typingEventInventoryCache[key] = TypingEventInventoryCacheEntry(
            metadata: metadata,
            inventory: inventory
        )
        testProbe?.recordInventoryScan()
        return inventory
    }

    private func cacheInventory(_ inventory: TypingEventInventory) {
        typingEventInventoryCache[Self.normalizedPath(for: eventsFileURL)] = TypingEventInventoryCacheEntry(
            metadata: fileMetadata(),
            inventory: inventory
        )
    }

    private func compactPendingSynchronously() throws -> (
        inventory: TypingEventInventory,
        droppedEventCount: Int,
        droppedByteCount: Int
    ) {
        let currentData = try Data(contentsOf: eventsFileURL)
        let lines = Self.lines(in: currentData)
        var retainedReversed: [Data] = []
        var retainedByteCount = 0
        for line in lines.reversed() {
            guard retainedReversed.count < retentionPolicy.compactedPendingEventCount else {
                break
            }
            if !retainedReversed.isEmpty,
               retainedByteCount + line.count > retentionPolicy.compactedPendingByteCount {
                break
            }
            retainedReversed.append(line)
            retainedByteCount += line.count
        }
        let retainedLines = retainedReversed.reversed()
        var retainedData = Data(capacity: retainedByteCount)
        retainedLines.forEach { retainedData.append($0) }
        try retainedData.write(to: eventsFileURL, options: .atomic)
        testProbe?.recordAtomicRewrite()
        let retainedInventory = inventory(for: retainedData)
        cacheInventory(retainedInventory)
        return (
            retainedInventory,
            max(0, lines.count - retainedInventory.eventCount),
            max(0, currentData.count - retainedData.count)
        )
    }

    private func fullSnapshotSynchronously() throws -> TypingEventSnapshot {
        guard fileManager.fileExists(atPath: eventsFileURL.path) else {
            return TypingEventSnapshot(
                rawData: Data(),
                requestData: Data(),
                events: [],
                claimedEventCount: 0
            )
        }
        return decodeSnapshot(try Data(contentsOf: eventsFileURL))
    }

    private func readDigestPrefixSynchronously() throws -> Data {
        let handle = try FileHandle(forReadingFrom: eventsFileURL)
        defer { try? handle.close() }
        var buffer = Data()
        let chunkSize = 64 * 1_024
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            let reachedEnd = chunk.isEmpty
            buffer.append(chunk)
            let prefix = digestPrefixLength(in: buffer, reachedEnd: reachedEnd)
            if prefix.shouldStop {
                return Data(buffer.prefix(prefix.byteCount))
            }
            if reachedEnd {
                return buffer
            }
        }
    }

    private func digestPrefixLength(in data: Data, reachedEnd: Bool) -> (byteCount: Int, shouldStop: Bool) {
        var claimedCount = 0
        var claimedByteCount = 0
        var lineStart = data.startIndex
        for index in data.indices where data[index] == 0x0A {
            let lineEnd = data.index(after: index)
            let lineByteCount = data.distance(from: lineStart, to: lineEnd)
            if claimedCount > 0,
               (claimedCount >= retentionPolicy.maximumDigestEventCount
                || claimedByteCount + lineByteCount > retentionPolicy.maximumDigestByteCount) {
                return (claimedByteCount, true)
            }
            claimedCount += 1
            claimedByteCount += lineByteCount
            lineStart = lineEnd
            if claimedCount >= retentionPolicy.maximumDigestEventCount
                || claimedByteCount >= retentionPolicy.maximumDigestByteCount {
                return (claimedByteCount, true)
            }
        }
        if reachedEnd, lineStart < data.endIndex {
            let trailingByteCount = data.distance(from: lineStart, to: data.endIndex)
            if claimedCount == 0
                || (claimedCount < retentionPolicy.maximumDigestEventCount
                    && claimedByteCount + trailingByteCount <= retentionPolicy.maximumDigestByteCount) {
                claimedByteCount += trailingByteCount
            }
            return (claimedByteCount, true)
        }
        if data.count >= retentionPolicy.maximumDigestByteCount, claimedByteCount > 0 {
            return (claimedByteCount, true)
        }
        return (claimedByteCount, false)
    }

    private func decodeSnapshot(_ rawData: Data) -> TypingEventSnapshot {
        let lines = Self.lines(in: rawData)
        var events: [AITypingEvent] = []
        var requestData = Data()
        for line in lines {
            guard let event = decodeEvent(line) else {
                continue
            }
            events.append(event)
            requestData.append(line)
            if requestData.last != 0x0A {
                requestData.append(0x0A)
            }
        }
        return TypingEventSnapshot(
            rawData: rawData,
            requestData: requestData,
            events: events,
            claimedEventCount: lines.count
        )
    }

    private func inventory(for data: Data) -> TypingEventInventory {
        let lines = Self.lines(in: data)
        var protectedCount = 0
        for line in lines {
            if let event = decodeEvent(line), Self.isProtectedOnlyEvent(event) {
                protectedCount += 1
            }
        }
        return TypingEventInventory(
            eventCount: lines.count,
            byteCount: data.count,
            protectedEventCount: protectedCount
        )
    }

    private func decodeEvent(_ line: Data) -> AITypingEvent? {
        var payload = line
        if payload.last == 0x0A {
            payload.removeLast()
        }
        if payload.last == 0x0D {
            payload.removeLast()
        }
        guard !payload.isEmpty else {
            return nil
        }
        return try? decoder.decode(AITypingEvent.self, from: payload)
    }

    private func archivePendingEventsSynchronously(
        matchingRawData rawData: Data,
        pruneProcessedArchives: Bool,
        beforeArchive: @Sendable () throws -> Void = {}
    ) throws -> TypingEventArchiveResult {
        guard !rawData.isEmpty,
              fileManager.fileExists(atPath: eventsFileURL.path) else {
            return .empty
        }
        let currentData = try Data(contentsOf: eventsFileURL)
        guard currentData.starts(with: rawData) else {
            throw TypingEventStoreError.pendingContentChanged
        }
        try beforeArchive()
        try fileManager.createDirectory(at: processedDirectoryURL, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let filename = "typing-events-\(formatter.string(from: now()).replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString).jsonl"
        let destination = processedDirectoryURL.appendingPathComponent(filename)
        try rawData.write(to: destination, options: .atomic)

        let remainingData = Data(currentData.dropFirst(rawData.count))
        if remainingData.isEmpty {
            try fileManager.removeItem(at: eventsFileURL)
        } else {
            try remainingData.write(to: eventsFileURL, options: .atomic)
        }
        testProbe?.recordAtomicRewrite()
        cacheInventory(inventory(for: remainingData))
        return pruneProcessedArchives ? pruneProcessedArchivesSynchronously() : .empty
    }

    private func pruneProcessedArchivesSynchronously() -> TypingEventArchiveResult {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: processedDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }
        struct Archive {
            var url: URL
            var date: Date
            var byteCount: Int
        }
        var archives = urls.compactMap { url -> Archive? in
            guard url.lastPathComponent.hasPrefix("typing-events-"),
                  url.pathExtension == "jsonl" else {
                return nil
            }
            guard let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey
            ]), values.isRegularFile != false else {
                return nil
            }
            return Archive(
                url: url,
                date: values.contentModificationDate ?? .distantPast,
                byteCount: values.fileSize ?? 0
            )
        }
        archives.sort { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.url.lastPathComponent < rhs.url.lastPathComponent
            }
            return lhs.date < rhs.date
        }

        let cutoff = now().addingTimeInterval(-retentionPolicy.processedMaximumAge)
        var remainingCount = archives.count
        var remainingBytes = archives.reduce(0) { $0 + $1.byteCount }
        var deletedCount = 0
        var deletedBytes = 0
        for archive in archives {
            let expired = archive.date < cutoff
            let overCount = remainingCount > retentionPolicy.processedMaximumFileCount
            let overBytes = remainingBytes > retentionPolicy.processedMaximumByteCount
            guard expired || overCount || overBytes else {
                continue
            }
            if testProbe?.shouldFailArchiveDeletion() == true {
                continue
            }
            do {
                try fileManager.removeItem(at: archive.url)
                remainingCount -= 1
                remainingBytes -= archive.byteCount
                deletedCount += 1
                deletedBytes += archive.byteCount
            } catch {
                continue
            }
        }
        return TypingEventArchiveResult(
            deletedFileCount: deletedCount,
            deletedByteCount: deletedBytes
        )
    }

    private func fileMetadata() -> TypingEventFileMetadata? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: eventsFileURL.path),
              let byteCount = (attributes[.size] as? NSNumber)?.intValue else {
            return nil
        }
        return TypingEventFileMetadata(
            byteCount: byteCount,
            modificationDate: attributes[.modificationDate] as? Date,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }

    private static func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func lines(in data: Data) -> [Data] {
        guard !data.isEmpty else {
            return []
        }
        var lines: [Data] = []
        var start = data.startIndex
        for index in data.indices where data[index] == 0x0A {
            let end = data.index(after: index)
            if start < end {
                lines.append(Data(data[start..<end]))
            }
            start = end
        }
        if start < data.endIndex {
            lines.append(Data(data[start..<data.endIndex]))
        }
        return lines.filter { line in
            line.contains { $0 != 0x0A && $0 != 0x0D }
        }
    }

    static func isProtectedOnlyEvent(_ event: AITypingEvent) -> Bool {
        guard event.candidateSource == "protected" else {
            return false
        }
        let protectedValues = [event.rawInput, event.committedText].compactMap { $0 }
        return !protectedValues.isEmpty
            && protectedValues.allSatisfy { $0.hasPrefix("protected:") }
    }
}
