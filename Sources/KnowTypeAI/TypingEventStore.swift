import CryptoKit
import Foundation

public enum TypingEventStoreError: Error, Equatable {
    case pendingContentChanged
}

struct TypingEventInventory: Sendable, Equatable {
    var eventCount: Int
    var byteCount: Int
    var protectedEventCount: Int
    var unprotectedEventCount: Int

    static let empty = TypingEventInventory(
        eventCount: 0,
        byteCount: 0,
        protectedEventCount: 0,
        unprotectedEventCount: 0
    )

    var isProtectedOnly: Bool {
        protectedEventCount > 0 && unprotectedEventCount == 0
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
    var maximumDigestByteCount: Int = 48 * 1_024
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
    private var maximumBufferedReadBytes = 0
    private var failedArchiveDeletionsRemaining = 0
    private var failedPendingArchivesRemaining = 0

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

    var maximumBufferedReadByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumBufferedReadBytes
    }

    func failNextArchiveDeletions(_ count: Int) {
        lock.lock()
        failedArchiveDeletionsRemaining = max(0, count)
        lock.unlock()
    }

    func failNextPendingArchives(_ count: Int) {
        lock.lock()
        failedPendingArchivesRemaining = max(0, count)
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

    fileprivate func recordBufferedRead(byteCount: Int) {
        lock.lock()
        maximumBufferedReadBytes = max(maximumBufferedReadBytes, byteCount)
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

    fileprivate func shouldFailPendingArchive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failedPendingArchivesRemaining > 0 else {
            return false
        }
        failedPendingArchivesRemaining -= 1
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

    func appendBounded(
        _ event: AITypingEvent,
        preservingClaimedPrefix claimedPrefix: Data? = nil
    ) throws -> TypingEventAppendResult {
        try withTypingEventFileLock {
            var boundedEvent = event
            let rawResult = boundedText(event.rawInput)
            let committedResult = boundedText(event.committedText)
            let appBundleIDResult = boundedText(event.appBundleID)
            let appNameResult = boundedText(event.appName)
            let candidateSourceResult = boundedText(event.candidateSource)
            boundedEvent.rawInput = rawResult.text
            boundedEvent.committedText = committedResult.text
            boundedEvent.appBundleID = appBundleIDResult.text
            boundedEvent.appName = appNameResult.text
            boundedEvent.candidateSource = candidateSourceResult.text

            try fileManager.createDirectory(
                at: eventsFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let existingInventory = try inventorySynchronously(
                preservingClaimedPrefix: claimedPrefix
            )
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
            } else {
                inventory.unprotectedEventCount += 1
            }
            cacheInventory(inventory)

            var droppedEventCount = 0
            var droppedByteCount = 0
            if inventory.eventCount > retentionPolicy.maximumPendingEventCount
                || inventory.byteCount > retentionPolicy.maximumPendingByteCount {
                let compaction = try compactPendingSynchronously(
                    preservingClaimedPrefix: claimedPrefix,
                    originalEventCount: inventory.eventCount
                )
                inventory = compaction.inventory
                droppedEventCount = compaction.droppedEventCount
                droppedByteCount = compaction.droppedByteCount
            }

            return TypingEventAppendResult(
                inventory: inventory,
                truncatedScalarCount: rawResult.removedScalarCount
                    + committedResult.removedScalarCount
                    + appBundleIDResult.removedScalarCount
                    + appNameResult.removedScalarCount
                    + candidateSourceResult.removedScalarCount,
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
            return decodeSnapshot(
                rawData,
                requestByteLimit: retentionPolicy.maximumDigestByteCount
            )
        }
    }

    func pendingDigestSnapshot(
        prefixByteCount: Int,
        eventCount: Int
    ) throws -> TypingEventSnapshot {
        guard prefixByteCount >= 0,
              eventCount >= 0,
              prefixByteCount <= retentionPolicy.maximumDigestByteCount else {
            throw TypingEventStoreError.pendingContentChanged
        }
        return try withTypingEventFileLock {
            testProbe?.recordDigestSnapshotDecode()
            guard prefixByteCount > 0 else {
                guard eventCount == 0 else {
                    throw TypingEventStoreError.pendingContentChanged
                }
                return TypingEventSnapshot(
                    rawData: Data(),
                    requestData: Data(),
                    events: [],
                    claimedEventCount: 0
                )
            }
            guard fileManager.fileExists(atPath: eventsFileURL.path) else {
                throw TypingEventStoreError.pendingContentChanged
            }
            let handle = try FileHandle(forReadingFrom: eventsFileURL)
            defer { try? handle.close() }
            let rawData = try readBounded(
                from: handle,
                offset: 0,
                byteCount: prefixByteCount
            )
            guard rawData.count == prefixByteCount else {
                throw TypingEventStoreError.pendingContentChanged
            }
            let snapshot = decodeSnapshot(
                rawData,
                requestByteLimit: retentionPolicy.maximumDigestByteCount
            )
            guard snapshot.claimedEventCount == eventCount else {
                throw TypingEventStoreError.pendingContentChanged
            }
            return snapshot
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
            if snapshot.events.isEmpty,
               snapshot.claimedEventCount > 0,
               snapshot.rawData.count >= retentionPolicy.maximumDigestByteCount {
                _ = try archiveOversizedDigestLineSynchronously(expectedRawData: snapshot.rawData)
                return
            }
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

    func hasProcessedArchive(prefixSHA256: String, byteCount: Int) -> Bool {
        guard prefixSHA256.count == 64,
              prefixSHA256.allSatisfy(\.isHexDigit),
              byteCount >= 0 else { return false }
        let url = processedDirectoryURL.appendingPathComponent("typing-events-\(prefixSHA256).jsonl")
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile != false,
              values.fileSize == byteCount else { return false }
        return true
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

    private func boundedText(_ text: String) -> (text: String, removedScalarCount: Int) {
        let result = boundedText(Optional(text))
        return (result.text ?? "", result.removedScalarCount)
    }

    private func inventorySynchronously(
        preservingClaimedPrefix claimedPrefix: Data? = nil
    ) throws -> TypingEventInventory {
        let key = Self.normalizedPath(for: eventsFileURL)
        let metadata = fileMetadata()
        if let cached = typingEventInventoryCache[key], cached.metadata == metadata {
            return cached.inventory
        }
        if let metadata,
           metadata.byteCount > retentionPolicy.maximumPendingByteCount {
            let compaction = try compactPendingSynchronously(
                preservingClaimedPrefix: claimedPrefix,
                originalEventCount: nil
            )
            testProbe?.recordInventoryScan()
            return compaction.inventory
        }
        let data: Data
        if fileManager.fileExists(atPath: eventsFileURL.path) {
            data = try Data(contentsOf: eventsFileURL)
            testProbe?.recordBufferedRead(byteCount: data.count)
        } else {
            data = Data()
        }
        let lines = Self.lines(in: data)
        let inventory = inventory(for: lines, byteCount: data.count)
        if inventory.eventCount > retentionPolicy.maximumPendingEventCount
            || inventory.byteCount > retentionPolicy.maximumPendingByteCount
            || lines.contains(where: { $0.count > retentionPolicy.maximumDigestByteCount }) {
            let compaction = try compactPendingSynchronously(
                preservingClaimedPrefix: claimedPrefix,
                originalEventCount: inventory.eventCount
            )
            testProbe?.recordInventoryScan()
            return compaction.inventory
        }
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

    private func compactPendingSynchronously(
        preservingClaimedPrefix claimedPrefix: Data?,
        originalEventCount: Int?
    ) throws -> (
        inventory: TypingEventInventory,
        droppedEventCount: Int,
        droppedByteCount: Int
    ) {
        let originalByteCount = fileMetadata()?.byteCount ?? 0
        let handle = try FileHandle(forReadingFrom: eventsFileURL)
        defer { try? handle.close() }
        let retainedPrefix: Data
        if let claimedPrefix,
           !claimedPrefix.isEmpty,
           claimedPrefix.count <= retentionPolicy.compactedPendingByteCount,
           claimedPrefix.count <= originalByteCount,
           try readBounded(
               from: handle,
               offset: 0,
               byteCount: claimedPrefix.count
           ) == claimedPrefix {
            retainedPrefix = claimedPrefix
        } else {
            retainedPrefix = Data()
        }
        let retainedPrefixEventCount = Self.lines(in: retainedPrefix).count
        let availableEventCount = max(
            0,
            retentionPolicy.compactedPendingEventCount - retainedPrefixEventCount
        )
        let availableByteCount = max(
            0,
            retentionPolicy.compactedPendingByteCount - retainedPrefix.count
        )
        let tailStart = retainedPrefix.count
        let suffixStart = max(tailStart, originalByteCount - availableByteCount)
        var tailData = try readBounded(
            from: handle,
            offset: suffixStart,
            byteCount: max(0, originalByteCount - suffixStart)
        )
        if suffixStart > tailStart {
            let precedingByte = try readBounded(
                from: handle,
                offset: suffixStart - 1,
                byteCount: 1
            ).first
            if precedingByte != 0x0A {
                if let newline = tailData.firstIndex(of: 0x0A) {
                    tailData = Data(tailData[tailData.index(after: newline)...])
                } else {
                    tailData = Data()
                }
            }
        }
        let tailLines = Self.lines(in: tailData)
        var retainedReversed: [Data] = []
        var retainedByteCount = 0
        for line in tailLines.reversed() {
            guard retainedReversed.count < availableEventCount else {
                break
            }
            guard line.count <= retentionPolicy.maximumDigestByteCount else {
                continue
            }
            guard retainedByteCount + line.count <= availableByteCount else {
                continue
            }
            retainedReversed.append(line)
            retainedByteCount += line.count
        }
        let retainedLines = retainedReversed.reversed()
        var retainedData = Data(capacity: retainedPrefix.count + retainedByteCount)
        retainedData.append(retainedPrefix)
        retainedLines.forEach { retainedData.append($0) }
        try retainedData.write(to: eventsFileURL, options: .atomic)
        testProbe?.recordAtomicRewrite()
        let retainedInventory = inventory(for: retainedData)
        cacheInventory(retainedInventory)
        return (
            retainedInventory,
            originalEventCount.map { max(0, $0 - retainedInventory.eventCount) }
                ?? (originalByteCount > retainedData.count ? 1 : 0),
            max(0, originalByteCount - retainedData.count)
        )
    }

    private func readBounded(
        from handle: FileHandle,
        offset: Int,
        byteCount: Int
    ) throws -> Data {
        guard byteCount > 0 else {
            return Data()
        }
        try handle.seek(toOffset: UInt64(offset))
        var data = Data()
        data.reserveCapacity(byteCount)
        while data.count < byteCount {
            let remaining = byteCount - data.count
            let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)) ?? Data()
            guard !chunk.isEmpty else {
                break
            }
            data.append(chunk)
        }
        testProbe?.recordBufferedRead(byteCount: data.count)
        return data
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
            let remainingByteBudget = max(
                1,
                retentionPolicy.maximumDigestByteCount - buffer.count
            )
            let chunk = try handle.read(
                upToCount: min(chunkSize, remainingByteBudget)
            ) ?? Data()
            let reachedEnd = chunk.isEmpty
            buffer.append(chunk)
            testProbe?.recordBufferedRead(byteCount: buffer.count)
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
            if claimedCount == 0 {
                claimedByteCount += min(
                    trailingByteCount,
                    retentionPolicy.maximumDigestByteCount
                )
            } else if claimedCount < retentionPolicy.maximumDigestEventCount
                && claimedByteCount + trailingByteCount <= retentionPolicy.maximumDigestByteCount {
                claimedByteCount += trailingByteCount
            }
            return (claimedByteCount, true)
        }
        if data.count >= retentionPolicy.maximumDigestByteCount {
            return (
                claimedByteCount > 0
                    ? claimedByteCount
                    : retentionPolicy.maximumDigestByteCount,
                true
            )
        }
        return (claimedByteCount, false)
    }

    private func decodeSnapshot(
        _ rawData: Data,
        requestByteLimit: Int? = nil
    ) -> TypingEventSnapshot {
        let lines = Self.lines(in: rawData)
        var events: [AITypingEvent] = []
        var requestData = Data()
        for line in lines {
            guard let event = decodeEvent(line) else {
                continue
            }
            var requestLine = line
            if requestLine.last != 0x0A {
                requestLine.append(0x0A)
            }
            if let requestByteLimit,
               requestData.count + requestLine.count > requestByteLimit {
                continue
            }
            events.append(event)
            requestData.append(requestLine)
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
        return inventory(for: lines, byteCount: data.count)
    }

    private func inventory(
        for lines: [Data],
        byteCount: Int
    ) -> TypingEventInventory {
        var protectedCount = 0
        var unprotectedCount = 0
        for line in lines {
            guard let event = decodeEvent(line) else {
                continue
            }
            if Self.isProtectedOnlyEvent(event) {
                protectedCount += 1
            } else {
                unprotectedCount += 1
            }
        }
        return TypingEventInventory(
            eventCount: lines.count,
            byteCount: byteCount,
            protectedEventCount: protectedCount,
            unprotectedEventCount: unprotectedCount
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
        let handle = try FileHandle(forReadingFrom: eventsFileURL)
        defer { try? handle.close() }
        let currentData = try readBounded(
            from: handle,
            offset: 0,
            byteCount: retentionPolicy.maximumPendingByteCount + 1
        )
        guard currentData.count <= retentionPolicy.maximumPendingByteCount,
              currentData.starts(with: rawData) else {
            throw TypingEventStoreError.pendingContentChanged
        }
        if testProbe?.shouldFailPendingArchive() == true {
            throw TypingEventStoreError.pendingContentChanged
        }
        try beforeArchive()
        try fileManager.createDirectory(at: processedDirectoryURL, withIntermediateDirectories: true)
        let filename = archiveFilename(for: rawData)
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

    private func archiveOversizedDigestLineSynchronously(expectedRawData: Data) throws -> TypingEventArchiveResult {
        guard fileManager.fileExists(atPath: eventsFileURL.path) else { return .empty }
        let handle = try FileHandle(forReadingFrom: eventsFileURL)
        defer { try? handle.close() }
        let currentData = try readBounded(
            from: handle,
            offset: 0,
            byteCount: retentionPolicy.maximumPendingByteCount + 1
        )
        guard currentData.count <= retentionPolicy.maximumPendingByteCount,
              currentData.starts(with: expectedRawData) else {
            throw TypingEventStoreError.pendingContentChanged
        }
        guard !currentData.isEmpty else { return .empty }
        let lineEnd = currentData.firstIndex(of: 0x0A).map { currentData.index(after: $0) } ?? currentData.endIndex
        let line = Data(currentData[..<lineEnd])
        try fileManager.createDirectory(at: processedDirectoryURL, withIntermediateDirectories: true)
        try line.write(to: processedDirectoryURL.appendingPathComponent(archiveFilename(for: line)), options: .atomic)
        let remainingData = Data(currentData[lineEnd...])
        if remainingData.isEmpty {
            try fileManager.removeItem(at: eventsFileURL)
        } else {
            try remainingData.write(to: eventsFileURL, options: .atomic)
        }
        testProbe?.recordAtomicRewrite()
        cacheInventory(inventory(for: remainingData))
        return .empty
    }

    private func archiveFilename(for data: Data) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "typing-events-\(digest).jsonl"
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
