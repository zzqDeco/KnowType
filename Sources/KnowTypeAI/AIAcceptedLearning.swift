import Darwin
import CryptoKit
import Foundation
import KnowTypeCore

let acceptedLearningFileLock = NSLock()

func acceptedLearningLockURL(historyURL: URL?) -> URL? {
    historyURL?.deletingLastPathComponent().appendingPathComponent("accepted-ai-learning.lock")
}

func acceptedLearningClearMarkerURL(historyURL: URL?) -> URL? {
    historyURL?.deletingLastPathComponent().appendingPathComponent("accepted-ai-learning.clear.json")
}

func acceptedLearningEvictedCommitsURL(historyURL: URL?) -> URL? {
    historyURL?.deletingLastPathComponent().appendingPathComponent("accepted-ai-learning.evicted-commits.json")
}

func acceptedLearningNormalizedCommitText(_ text: String) -> String {
    text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}

func acceptedLearningCommitTextDigest(_ text: String) -> String {
    let clean = acceptedLearningNormalizedCommitText(text)
    return SHA256.hash(data: Data(clean.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

func acceptedLearningCommitTextVariants(from records: [AIAcceptedLearningRecord]) -> [String] {
    var orderedReversed: [String] = []
    var seen: Set<String> = []
    for record in records.reversed() {
        let clean = acceptedLearningNormalizedCommitText(record.acceptedText)
        guard !clean.isEmpty else {
            continue
        }
        let variants = clean.count <= 48
            ? [clean]
            : [clean, String(clean.prefix(48)) + "..."]
        for variant in variants.reversed() where seen.insert(variant).inserted {
            orderedReversed.append(variant)
        }
    }
    return orderedReversed.reversed()
}

func acceptedLearningCommitDigestVariants(from records: [AIAcceptedLearningRecord]) -> [String] {
    var orderedReversed: [String] = []
    var seen: Set<String> = []
    for variant in acceptedLearningCommitTextVariants(from: records).reversed() {
        let digest = acceptedLearningCommitTextDigest(variant)
        if seen.insert(digest).inserted {
            orderedReversed.append(digest)
        }
    }
    return orderedReversed.reversed()
}

func isAcceptedLearningNoSuchFileError(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
        return true
    }
    if nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOENT {
        return true
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
        return isAcceptedLearningNoSuchFileError(underlying)
    }
    return false
}

func loadAcceptedLearningEvictedCommitListOrThrow(
    from url: URL?,
    fileManager: FileManager = .default
) throws -> [String] {
    guard let url else {
        return []
    }
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        if isAcceptedLearningNoSuchFileError(error) || !fileManager.fileExists(atPath: url.path) {
            return []
        }
        throw error
    }
    let decoded = try JSONDecoder().decode([String].self, from: data)
    var orderedReversed: [String] = []
    var seen: Set<String> = []
    for entry in decoded.reversed() where seen.insert(entry).inserted {
        orderedReversed.append(entry)
    }
    return orderedReversed.reversed()
}

func loadAcceptedLearningEvictedCommitList(
    from url: URL?,
    fileManager: FileManager = .default
) -> [String] {
    (try? loadAcceptedLearningEvictedCommitListOrThrow(from: url, fileManager: fileManager)) ?? []
}

func loadAcceptedLearningEvictedCommits(
    from url: URL?,
    fileManager: FileManager = .default
) -> Set<String> {
    Set(loadAcceptedLearningEvictedCommitList(from: url, fileManager: fileManager))
}

func recordAcceptedLearningEvictedCommits(
    _ evictedRecords: [AIAcceptedLearningRecord],
    historyURL: URL?,
    evictedCommitsURL: URL? = nil,
    maxEntries: Int = 4_096,
    fileManager: FileManager = .default
) throws {
    guard let evictedURL = evictedCommitsURL ?? acceptedLearningEvictedCommitsURL(historyURL: historyURL) else {
        return
    }
    let newDigests = acceptedLearningCommitDigestVariants(from: evictedRecords)
    guard !newDigests.isEmpty else {
        return
    }
    let newDigestSet = Set(newDigests)
    let existing = try loadAcceptedLearningEvictedCommitListOrThrow(from: evictedURL, fileManager: fileManager)
    let effectiveMaxEntries = max(4_096, maxEntries)
    let merged = (existing.filter { !newDigestSet.contains($0) } + newDigests).suffix(effectiveMaxEntries)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(Array(merged))
    try fileManager.createDirectory(
        at: evictedURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: evictedURL, options: .atomic)
}

func withAcceptedLearningFileLock<T>(
    lockURL: URL?,
    fileManager: FileManager = .default,
    _ body: () throws -> T
) throws -> T {
    acceptedLearningFileLock.lock()
    defer {
        acceptedLearningFileLock.unlock()
    }

    guard let lockURL else {
        return try body()
    }

    try fileManager.createDirectory(
        at: lockURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    if !fileManager.fileExists(atPath: lockURL.path) {
        fileManager.createFile(atPath: lockURL.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: lockURL)
    defer {
        try? handle.close()
    }
    guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer {
        flock(handle.fileDescriptor, LOCK_UN)
    }
    return try body()
}

func withExistingAcceptedLearningFileLock<T, R>(
    lockURL: URL?,
    fileManager: FileManager = .default,
    _ body: () throws -> T,
    commit: (T) throws -> R
) throws -> R {
    acceptedLearningFileLock.lock()
    defer {
        acceptedLearningFileLock.unlock()
    }

    guard let lockURL else {
        return try commit(body())
    }
    if !fileManager.fileExists(atPath: lockURL.path) {
        let initialResult = try body()
        guard fileManager.fileExists(atPath: lockURL.path) else {
            return try commit(initialResult)
        }
    }
    let handle = try FileHandle(forWritingTo: lockURL)
    defer {
        try? handle.close()
    }
    guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer {
        flock(handle.fileDescriptor, LOCK_UN)
    }
    return try commit(body())
}

func withExistingAcceptedLearningFileLock<T>(
    lockURL: URL?,
    fileManager: FileManager = .default,
    _ body: () throws -> T
) throws -> T {
    try withExistingAcceptedLearningFileLock(
        lockURL: lockURL,
        fileManager: fileManager,
        body,
        commit: { $0 }
    )
}

public struct AIAcceptedLearningRecord: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var acceptedAt: Date
    public var acceptID: UUID?
    public var schemaID: String
    public var appBundleID: String?
    public var rawInput: String?
    public var lockedPrefix: String?
    public var acceptedText: String
    public var provider: String
    public var contextVersion: String
    public var textHash: String
    public var commitKind: String
    public var candidateSource: String
    public var extractedTerms: [LexicalContextTerm]

    public init(
        schemaVersion: Int = 1,
        acceptedAt: Date = Date(),
        acceptID: UUID? = nil,
        schemaID: String,
        appBundleID: String? = nil,
        rawInput: String? = nil,
        lockedPrefix: String? = nil,
        acceptedText: String,
        provider: String,
        contextVersion: String,
        textHash: String? = nil,
        commitKind: String = "ai",
        candidateSource: String,
        extractedTerms: [LexicalContextTerm]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.acceptedAt = acceptedAt
        self.acceptID = acceptID
        self.schemaID = schemaID
        self.appBundleID = appBundleID
        self.rawInput = rawInput
        self.lockedPrefix = lockedPrefix
        self.acceptedText = acceptedText
        self.provider = provider
        self.contextVersion = contextVersion
        self.textHash = textHash ?? Self.hash(acceptedText)
        self.commitKind = commitKind
        self.candidateSource = candidateSource
        self.extractedTerms = extractedTerms ?? AIAcceptedTermExtractor().extractTerms(from: acceptedText)
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct AIAcceptedLanguageSummary: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var historyHash: String
    public var acceptedCount: Int
    public var termProfile: [LexicalContextTerm]
    public var styleProfile: ToneProfile
    public var recentAcceptedCommits: [String]
    public var sourceSummary: [String]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        historyHash: String,
        acceptedCount: Int,
        termProfile: [LexicalContextTerm],
        styleProfile: ToneProfile,
        recentAcceptedCommits: [String],
        sourceSummary: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.historyHash = historyHash
        self.acceptedCount = acceptedCount
        self.termProfile = termProfile
        self.styleProfile = styleProfile
        self.recentAcceptedCommits = recentAcceptedCommits
        self.sourceSummary = sourceSummary
    }
}

public protocol AIAcceptedLearningRecording: Sendable {
    func recordAcceptedAI(_ record: AIAcceptedLearningRecord) async
}

public protocol AIAcceptedLearningSnapshotProviding: Sendable {
    func snapshot() -> AIAcceptedLanguageSummary?
    func snapshot(schemaID: String?) -> AIAcceptedLanguageSummary?
}

public struct AIAcceptedLearningSummaryReadyEvent: Sendable, Equatable {
    public var schemaID: String
    public var historyHash: String
    public var acceptedCount: Int
    public var termCount: Int
    public var recentCommitCount: Int

    public init(
        schemaID: String,
        historyHash: String,
        acceptedCount: Int,
        termCount: Int,
        recentCommitCount: Int
    ) {
        self.schemaID = schemaID
        self.historyHash = historyHash
        self.acceptedCount = acceptedCount
        self.termCount = termCount
        self.recentCommitCount = recentCommitCount
    }
}

public protocol AIAcceptedLearningSummaryObserving: Sendable {
    @discardableResult
    func addSummaryReadyObserver(
        _ observer: @escaping @Sendable (AIAcceptedLearningSummaryReadyEvent) -> Void
    ) -> UUID
    func removeSummaryReadyObserver(_ id: UUID)
}

public extension AIAcceptedLearningSnapshotProviding {
    func snapshot(schemaID _: String?) -> AIAcceptedLanguageSummary? {
        snapshot()
    }
}

public struct AIAcceptedTermExtractor: Sendable {
    public var maxTerms: Int

    public init(maxTerms: Int = 24) {
        self.maxTerms = max(1, maxTerms)
    }

    public func extractTerms(from text: String) -> [LexicalContextTerm] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !TextProtection.containsSecretLikeContent(clean),
              !TextProtection.requiresNoCorrection(clean) else {
            return []
        }

        var counts: [String: Int] = [:]
        addTechnicalTerms(from: clean, to: &counts)
        addHanTerms(from: clean, to: &counts)

        return counts
            .map { term, count in
                LexicalContextTerm(
                    text: term,
                    score: min(1, 0.52 + Double(count) * 0.12),
                    source: "accepted-ai"
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.text < rhs.text
                }
                return lhs.score > rhs.score
            }
            .prefix(maxTerms)
            .map { $0 }
    }

    private func addTechnicalTerms(from text: String, to counts: inout [String: Int]) {
        let tokens = matches(#"\b[A-Za-z][A-Za-z0-9_+.-]{1,}\b"#, in: text)
            .map { token -> String in
                TextProtection.canonicalTechnicalToken(token) ?? token
            }
            .filter { token in
                token.count >= 2 && token.count <= 32
            }

        for token in tokens where isInjectableToken(token) {
            counts[token, default: 0] += 1
        }

        for index in tokens.indices.dropLast() {
            let phrase = "\(tokens[index]) \(tokens[index + 1])"
            guard phrase.count <= 40,
                  phrase.range(of: #"[A-Z_]"#, options: .regularExpression) != nil else {
                continue
            }
            counts[phrase, default: 0] += 1
        }
    }

    private func addHanTerms(from text: String, to counts: inout [String: Int]) {
        for run in matches(#"\p{Han}+"#, in: text) {
            let chars = Array(run)
            if (2...8).contains(chars.count) {
                let term = String(chars)
                if isUsefulHanTerm(term) {
                    counts[term, default: 0] += 1
                }
                continue
            }
            guard chars.count > 8 else {
                continue
            }
            for width in 2...4 {
                guard chars.count >= width else {
                    continue
                }
                for start in 0...(chars.count - width) {
                    let term = String(chars[start..<(start + width)])
                    if isUsefulHanTerm(term) {
                        counts[term, default: 0] += 1
                    }
                }
            }
        }
    }

    private func isInjectableToken(_ token: String) -> Bool {
        guard LexicalContextBuilder.sanitizedAcceptedProfileText(token) != nil else {
            return false
        }
        if TextProtection.canonicalTechnicalToken(token) != nil {
            return true
        }
        return token.range(of: #"[A-Z_]"#, options: .regularExpression) != nil
            || token.count >= 3
    }

    private func isUsefulHanTerm(_ term: String) -> Bool {
        let stopTerms: Set<String> = [
            "这个", "那个", "就是", "然后", "所以", "但是", "可以", "需要", "觉得",
            "我们", "你们", "他们", "一个", "一下", "这里", "那里"
        ]
        return !stopTerms.contains(term)
            && LexicalContextBuilder.sanitizedAcceptedProfileText(term) != nil
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            return String(text[range])
        }
    }
}

private final class LiveAcceptedLearningStoreRegistry: @unchecked Sendable {
    static let shared = LiveAcceptedLearningStoreRegistry()

    private struct Entry {
        weak var store: AIAcceptedLearningStore?
    }

    private let lock = NSLock()
    private var entriesByKey: [String: [Entry]] = [:]

    func register(_ store: AIAcceptedLearningStore, historyURL: URL?) {
        guard let key = Self.canonicalKey(for: historyURL) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        var entries = entriesByKey[key, default: []].filter { $0.store != nil && $0.store !== store }
        entries.append(Entry(store: store))
        entriesByKey[key] = entries
    }

    func peerStores(
        for historyURL: URL?,
        excluding excludedStore: AIAcceptedLearningStore? = nil
    ) -> [AIAcceptedLearningStore] {
        guard let key = Self.canonicalKey(for: historyURL) else {
            return []
        }
        lock.lock()
        defer { lock.unlock() }
        guard let entries = entriesByKey[key] else {
            return []
        }
        let liveEntries = entries.filter { $0.store != nil }
        if liveEntries.isEmpty {
            entriesByKey.removeValue(forKey: key)
            return []
        }
        entriesByKey[key] = liveEntries
        return liveEntries.compactMap { entry in
            guard let store = entry.store, store !== excludedStore else {
                return nil
            }
            return store
        }
    }

    private static func canonicalKey(for url: URL?) -> String? {
        url?.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

func synchronizePeerAcceptedLearningStores(
    for historyURL: URL?,
    excluding excludedStore: AIAcceptedLearningStore? = nil
) {
    let peers = LiveAcceptedLearningStoreRegistry.shared.peerStores(
        for: historyURL,
        excluding: excludedStore
    )
    for peer in peers {
        peer.synchronizeWithDiskState()
    }
}

public final class AIAcceptedLearningStore:
    AIAcceptedLearningRecording,
    AIAcceptedLearningSnapshotProviding,
    AIAcceptedLearningSummaryObserving,
    @unchecked Sendable
{
    public static let defaultMaxRecordCount = 500
    private static let startupRepairRetryInterval: TimeInterval = 5.0

    private struct FileMetadataStamp: Equatable, Sendable {
        var exists: Bool
        var fileNumber: UInt64?
        var size: UInt64?
        var modificationDate: Date?
        var permissions: UInt16?
    }

    private struct DiskStateMetadata: Equatable, Sendable {
        var history: FileMetadataStamp
        var clearMarker: FileMetadataStamp
        var evictedCommits: FileMetadataStamp
    }

    private struct RepairEnvironmentStamp: Equatable, Sendable {
        var directory: FileMetadataStamp
        var summaryDirectory: FileMetadataStamp
        var mirrorDirectory: FileMetadataStamp
        var history: FileMetadataStamp
        var summary: FileMetadataStamp
        var mirror: FileMetadataStamp
        var evictedCommits: FileMetadataStamp
    }

    public let maxRecordCount: Int
    private let historyURL: URL?
    private let summaryURL: URL?
    private let mirrorURL: URL?
    private let fileManager: FileManager
    private let diagnosticSink: any AIRecommendationDiagnosticSink
    private let summaryDelayNanoseconds: UInt64
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()
    private var records: [AIAcceptedLearningRecord]
    private var summary: AIAcceptedLanguageSummary?
    private var schemaSummaries: [String: AIAcceptedLanguageSummary]
    private var pendingSummarySchemaIDs: Set<String>
    private var summaryTask: Task<Void, Never>?
    private var isSummaryRebuildScheduled = false
    private var summaryObservers: [UUID: @Sendable (AIAcceptedLearningSummaryReadyEvent) -> Void] = [:]
    private var lastClearMarkerModifiedAt: Date?
    private var lastDiskStateMetadata: DiskStateMetadata?
    private var pendingStartupRepair: Bool
    private var pendingStartupSummaryWrite: Bool
    private var lastStartupRepairAttemptAt: Date?
    private var lastFailedRepairEnvironmentStamp: RepairEnvironmentStamp?

    private struct StartupState {
        var records: [AIAcceptedLearningRecord]
        var summary: AIAcceptedLanguageSummary?
        var schemaSummaries: [String: AIAcceptedLanguageSummary]
        var lastClearMarkerModifiedAt: Date?
        var lastDiskStateMetadata: DiskStateMetadata?
        var needsCompaction: Bool = false
        var needsSummaryFileRepair: Bool = false
        var needsMirrorRefresh: Bool = false
        var didCompactHistoryOnDisk: Bool = false
        var repairError: (any Error)? = nil
    }

    public init(
        historyURL: URL? = AIAcceptedLearningStore.defaultHistoryURL(),
        summaryURL: URL? = AIAcceptedLearningStore.defaultSummaryURL(),
        mirrorURL: URL? = AIUserDirectory.defaultDirectory().acceptedLearningMirrorURL,
        fileManager: FileManager = .default,
        diagnosticSink: any AIRecommendationDiagnosticSink = NoopAIRecommendationDiagnosticSink(),
        summaryDelayNanoseconds: UInt64 = 2_000_000_000,
        maxRecordCount: Int = AIAcceptedLearningStore.defaultMaxRecordCount
    ) {
        let clampedMaxRecordCount = max(1, maxRecordCount)
        let configuredEncoder = JSONEncoder()
        configuredEncoder.dateEncodingStrategy = .iso8601
        let configuredDecoder = JSONDecoder()
        configuredDecoder.dateDecodingStrategy = .iso8601
        let startupState: StartupState
        let startupRepairErrorReason: String?
        var didCompactOnStartup = false
        do {
            let initialState = try withExistingAcceptedLearningFileLock(
                lockURL: acceptedLearningLockURL(historyURL: historyURL),
                fileManager: fileManager
            ) {
                try Self.loadStartupState(
                    historyURL: historyURL,
                    summaryURL: summaryURL,
                    mirrorURL: mirrorURL,
                    fileManager: fileManager,
                    encoder: configuredEncoder,
                    decoder: configuredDecoder,
                    maxRecordCount: clampedMaxRecordCount,
                    compactPersistentHistory: false,
                    repairPersistentSummary: false
                )
            }
            if (initialState.needsCompaction && historyURL != nil) || initialState.needsMirrorRefresh {
                do {
                    startupState = try withAcceptedLearningFileLock(
                        lockURL: acceptedLearningLockURL(historyURL: historyURL),
                        fileManager: fileManager
                    ) {
                        try Self.loadStartupState(
                            historyURL: historyURL,
                            summaryURL: summaryURL,
                            mirrorURL: mirrorURL,
                            fileManager: fileManager,
                            encoder: configuredEncoder,
                            decoder: configuredDecoder,
                            maxRecordCount: clampedMaxRecordCount,
                            compactPersistentHistory: true,
                            repairPersistentSummary: true,
                            forceSummaryFileRepair: initialState.needsCompaction && historyURL != nil
                        )
                    }
                    didCompactOnStartup = startupState.didCompactHistoryOnDisk
                    startupRepairErrorReason = startupState.repairError.map { String(describing: type(of: $0)) }
                } catch {
                    startupState = initialState
                    startupRepairErrorReason = String(describing: type(of: error))
                }
            } else {
                startupState = initialState
                startupRepairErrorReason = nil
            }
        } catch {
            startupState = StartupState(
                records: [],
                summary: Self.loadSummary(from: summaryURL, decoder: configuredDecoder),
                schemaSummaries: [:],
                lastClearMarkerModifiedAt: Self.fileModificationDate(
                    acceptedLearningClearMarkerURL(historyURL: historyURL),
                    fileManager: fileManager
                ),
                lastDiskStateMetadata: nil
            )
            startupRepairErrorReason = String(describing: type(of: error))
        }

        let requiresDeferredStartupRepair = startupRepairErrorReason != nil
            && ((startupState.needsCompaction && historyURL != nil)
                || startupState.needsSummaryFileRepair
                || startupState.needsMirrorRefresh
                || startupState.lastDiskStateMetadata == nil)
        self.maxRecordCount = clampedMaxRecordCount
        self.historyURL = historyURL
        self.summaryURL = summaryURL
        self.mirrorURL = mirrorURL
        self.fileManager = fileManager
        self.diagnosticSink = diagnosticSink
        self.summaryDelayNanoseconds = summaryDelayNanoseconds
        self.encoder = configuredEncoder
        self.decoder = configuredDecoder
        self.records = startupState.records
        self.lastClearMarkerModifiedAt = startupState.lastClearMarkerModifiedAt
        self.lastDiskStateMetadata = startupState.lastDiskStateMetadata
        self.pendingStartupRepair = requiresDeferredStartupRepair
        self.pendingStartupSummaryWrite = startupState.needsSummaryFileRepair
            || (startupState.needsCompaction && historyURL != nil)
        self.lastStartupRepairAttemptAt = requiresDeferredStartupRepair ? Date() : nil
        self.lastFailedRepairEnvironmentStamp = requiresDeferredStartupRepair
            ? Self.repairEnvironmentStamp(
                historyURL: historyURL,
                summaryURL: summaryURL,
                mirrorURL: mirrorURL,
                fileManager: fileManager
            )
            : nil
        self.summary = startupState.summary
        self.schemaSummaries = startupState.schemaSummaries
        self.pendingSummarySchemaIDs = []
        LiveAcceptedLearningStoreRegistry.shared.register(self, historyURL: historyURL)
        if didCompactOnStartup {
            synchronizePeerAcceptedLearningStores(for: historyURL, excluding: self)
        }
        if let startupRepairErrorReason {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .lexicalProfileFallback,
                    reason: "accepted_learning_summary_repair_failed:\(startupRepairErrorReason)"
                )
            )
        }
    }

    public static func inMemory(
        diagnosticSink: any AIRecommendationDiagnosticSink = NoopAIRecommendationDiagnosticSink(),
        maxRecordCount: Int = AIAcceptedLearningStore.defaultMaxRecordCount
    ) -> AIAcceptedLearningStore {
        AIAcceptedLearningStore(
            historyURL: nil,
            summaryURL: nil,
            mirrorURL: nil,
            diagnosticSink: diagnosticSink,
            summaryDelayNanoseconds: 0,
            maxRecordCount: maxRecordCount
        )
    }

    public static func defaultHistoryURL(fileManager: FileManager = .default) -> URL {
        defaultApplicationSupportAIDirectory(fileManager: fileManager)
            .appendingPathComponent("accepted-ai-learning.jsonl", isDirectory: false)
    }

    public static func defaultSummaryURL(fileManager: FileManager = .default) -> URL {
        defaultApplicationSupportAIDirectory(fileManager: fileManager)
            .appendingPathComponent("accepted-ai-summary.json", isDirectory: false)
    }

    public func recordAcceptedAI(_ record: AIAcceptedLearningRecord) async {
        let protectedValues = [record.rawInput, record.lockedPrefix, record.acceptedText].compactMap { $0 }
        guard !protectedValues.contains(where: TextProtection.containsSecretLikeContent) else {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedLearningSkippedSecret,
                    rawLength: record.rawInput?.count,
                    candidateCount: record.extractedTerms.count,
                    reason: "secret_like_text"
                )
            )
            return
        }

        do {
            try append(record)
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedLearningRecorded,
                    rawLength: record.rawInput?.count,
                    candidateCount: record.extractedTerms.count,
                    reason: "text_hash=\(String(record.textHash.prefix(8)))"
                )
            )
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .acceptedLearningTermsExtracted,
                    candidateCount: record.extractedTerms.count,
                    reason: "source=ai-accepted"
                )
            )
        } catch {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .lexicalProfileFallback,
                    reason: "accepted_learning_write_failed:\(String(describing: type(of: error)))"
                )
            )
        }
    }

    public func snapshot() -> AIAcceptedLanguageSummary? {
        syncRecordsAfterExternalClear()
        lock.lock()
        let current = summary
        lock.unlock()
        return current
    }

    public func snapshot(schemaID: String?) -> AIAcceptedLanguageSummary? {
        guard let schemaID else {
            return snapshot()
        }
        syncRecordsAfterExternalClear()
        lock.lock()
        let current = schemaSummaries[schemaID]
        lock.unlock()
        return current
    }

    public func allRecords() -> [AIAcceptedLearningRecord] {
        syncRecordsAfterExternalClear()
        lock.lock()
        let current = records
        lock.unlock()
        return current
    }

    @discardableResult
    public func addSummaryReadyObserver(
        _ observer: @escaping @Sendable (AIAcceptedLearningSummaryReadyEvent) -> Void
    ) -> UUID {
        let id = UUID()
        lock.lock()
        summaryObservers[id] = observer
        lock.unlock()
        return id
    }

    public func removeSummaryReadyObserver(_ id: UUID) {
        lock.lock()
        summaryObservers.removeValue(forKey: id)
        lock.unlock()
    }

    private func append(_ record: AIAcceptedLearningRecord) throws {
        var externalEvents: [AIAcceptedLearningSummaryReadyEvent] = []
        var didCompact = false
        try withAcceptedLearningFileLock(lockURL: acceptedLearningLockURL(historyURL: historyURL), fileManager: fileManager) {
            externalEvents = try syncRecordsAfterExternalClearLocked()
            var nextRecords: [AIAcceptedLearningRecord]
            if let historyURL, fileManager.fileExists(atPath: historyURL.path) {
                nextRecords = try Self.loadRecordsOrThrow(
                    from: historyURL,
                    decoder: decoder,
                    fileManager: fileManager
                )
            } else {
                lock.lock()
                nextRecords = records
                lock.unlock()
            }

            nextRecords.append(record)
            let evictedRecords: [AIAcceptedLearningRecord]
            let evictedSchemaIDs: Set<String>
            if nextRecords.count > maxRecordCount {
                let overflowCount = nextRecords.count - maxRecordCount
                evictedRecords = Array(nextRecords.prefix(overflowCount))
                evictedSchemaIDs = Set(evictedRecords.map(\.schemaID))
                nextRecords = Array(nextRecords.suffix(maxRecordCount))
                didCompact = true
            } else {
                evictedRecords = []
                evictedSchemaIDs = []
                didCompact = false
            }

            if let historyURL {
                if didCompact {
                    try recordAcceptedLearningEvictedCommits(
                        evictedRecords,
                        historyURL: historyURL,
                        fileManager: fileManager
                    )
                    try Self.writeRecords(
                        nextRecords,
                        to: historyURL,
                        encoder: encoder,
                        fileManager: fileManager
                    )
                } else {
                    try fileManager.createDirectory(
                        at: historyURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let data = try encoder.encode(record)
                    var line = data
                    line.append(0x0A)
                    if fileManager.fileExists(atPath: historyURL.path) {
                        let handle = try FileHandle(forWritingTo: historyURL)
                        defer { try? handle.close() }
                        try handle.seekToEnd()
                        try handle.write(contentsOf: line)
                    } else {
                        try line.write(to: historyURL, options: .atomic)
                    }
                }
            }
            let updatedMetadata = Self.diskStateMetadata(
                historyURL: historyURL,
                fileManager: fileManager
            )
            lock.lock()
            records = nextRecords
            lastDiskStateMetadata = updatedMetadata
            if didCompact {
                let generatedAt = Date()
                if summary != nil {
                    summary = Self.buildSummary(records: nextRecords, generatedAt: generatedAt)
                }
                for evictedSchemaID in evictedSchemaIDs where schemaSummaries[evictedSchemaID] != nil {
                    let retainedSchemaRecords = nextRecords.filter { $0.schemaID == evictedSchemaID }
                    schemaSummaries[evictedSchemaID] = Self.buildSummary(
                        records: retainedSchemaRecords,
                        generatedAt: generatedAt
                    )
                }
            }
            pendingSummarySchemaIDs.insert(record.schemaID)
            pendingSummarySchemaIDs.formUnion(evictedSchemaIDs)
            lock.unlock()
        }
        notifySummaryReady(externalEvents)
        if didCompact {
            synchronizePeerAcceptedLearningStores(for: historyURL, excluding: self)
        }
        scheduleSummaryRebuild()
    }

    private func scheduleSummaryRebuild() {
        lock.lock()
        summaryTask?.cancel()
        isSummaryRebuildScheduled = summaryDelayNanoseconds > 0
        lock.unlock()

        if summaryDelayNanoseconds == 0 {
            rebuildSummary()
            return
        }

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: self.summaryDelayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self.rebuildSummary()
        }
        lock.lock()
        summaryTask = task
        lock.unlock()
    }

    private func rebuildSummary() {
        var changedSchemaIDsForRetry: Set<String> = []
        do {
            let events = try withAcceptedLearningFileLock(
                lockURL: acceptedLearningLockURL(historyURL: historyURL),
                fileManager: fileManager
            ) { () -> [AIAcceptedLearningSummaryReadyEvent] in
                let externalEvents = try syncRecordsAfterExternalClearLocked()
                let currentRecords: [AIAcceptedLearningRecord]
                if let historyURL, fileManager.fileExists(atPath: historyURL.path) {
                    let loadedRecords = try Self.loadRecordsOrThrow(
                        from: historyURL,
                        decoder: decoder,
                        fileManager: fileManager
                    )
                    if loadedRecords.count > maxRecordCount {
                        let overflowCount = loadedRecords.count - maxRecordCount
                        let evictedRecords = Array(loadedRecords.prefix(overflowCount))
                        currentRecords = Array(loadedRecords.suffix(maxRecordCount))
                        try recordAcceptedLearningEvictedCommits(
                            evictedRecords,
                            historyURL: historyURL,
                            fileManager: fileManager
                        )
                        try Self.writeRecords(
                            currentRecords,
                            to: historyURL,
                            encoder: encoder,
                            fileManager: fileManager
                        )
                    } else {
                        currentRecords = loadedRecords
                    }
                } else {
                    lock.lock()
                    currentRecords = records
                    lock.unlock()
                }

                let updatedMetadata = Self.diskStateMetadata(
                    historyURL: historyURL,
                    fileManager: fileManager
                )
                lock.lock()
                let previousRecords = records
                records = currentRecords
                lastDiskStateMetadata = updatedMetadata
                var changedSchemaIDs = pendingSummarySchemaIDs.union(externalEvents.map(\.schemaID))
                if previousRecords != currentRecords {
                    let allSchemas = Set(previousRecords.map(\.schemaID)).union(currentRecords.map(\.schemaID))
                    for schemaID in allSchemas {
                        if previousRecords.filter({ $0.schemaID == schemaID }) != currentRecords.filter({ $0.schemaID == schemaID }) {
                            changedSchemaIDs.insert(schemaID)
                        }
                    }
                }
                changedSchemaIDsForRetry = changedSchemaIDs
                pendingSummarySchemaIDs.removeAll()
                lock.unlock()

                let generatedAt = Date()
                let nextSummary = Self.buildSummary(records: currentRecords, generatedAt: generatedAt)
                let nextSchemaSummaries = Self.buildSchemaSummaries(records: currentRecords, generatedAt: generatedAt)

                lock.lock()
                summary = nextSummary
                schemaSummaries = nextSchemaSummaries
                lock.unlock()

                try persistSummary(nextSummary)
                lock.lock()
                isSummaryRebuildScheduled = false
                pendingStartupRepair = false
                pendingStartupSummaryWrite = false
                lastStartupRepairAttemptAt = nil
                lastFailedRepairEnvironmentStamp = nil
                lock.unlock()
                return Self.summaryReadyEvents(
                    from: nextSchemaSummaries,
                    changedSchemaIDs: changedSchemaIDs
                )
            }
            notifySummaryReady(events)
            synchronizePeerAcceptedLearningStores(for: historyURL, excluding: self)
        } catch {
            let failedStamp = Self.repairEnvironmentStamp(
                historyURL: historyURL,
                summaryURL: summaryURL,
                mirrorURL: mirrorURL,
                fileManager: fileManager
            )
            lock.lock()
            isSummaryRebuildScheduled = false
            pendingSummarySchemaIDs.formUnion(changedSchemaIDsForRetry)
            if pendingStartupRepair {
                pendingStartupSummaryWrite = true
                lastStartupRepairAttemptAt = Date()
                lastFailedRepairEnvironmentStamp = failedStamp
            }
            lock.unlock()
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .lexicalProfileFallback,
                    reason: "accepted_learning_summary_write_failed:\(String(describing: type(of: error)))"
                )
            )
        }
    }

    private struct DiskSyncCandidate {
        let reloadedRecords: [AIAcceptedLearningRecord]
        let finalMetadata: DiskStateMetadata?
        let markerModifiedAt: Date?
    }

    private func loadDiskSyncCandidate() throws -> DiskSyncCandidate? {
        guard historyURL != nil else {
            return nil
        }
        let currentMetadata = Self.diskStateMetadata(
            historyURL: historyURL,
            fileManager: fileManager
        )
        let markerModifiedAt = currentMetadata?.clearMarker.modificationDate
        lock.lock()
        let markerChanged = markerModifiedAt != nil
            && (lastClearMarkerModifiedAt == nil || markerModifiedAt! > (lastClearMarkerModifiedAt ?? .distantPast))
        let metadataChanged = lastDiskStateMetadata == nil || currentMetadata != lastDiskStateMetadata
        let shouldReload = markerChanged || metadataChanged
        lock.unlock()
        guard shouldReload else {
            return nil
        }
        let loaded = try Self.loadRecordsWithMetadata(
            from: historyURL,
            decoder: decoder,
            fileManager: fileManager
        )
        let reloadedRecords = loaded.records.count > maxRecordCount
            ? Array(loaded.records.suffix(maxRecordCount))
            : loaded.records
        return DiskSyncCandidate(
            reloadedRecords: reloadedRecords,
            finalMetadata: loaded.metadata,
            markerModifiedAt: markerModifiedAt
        )
    }

    private func applyDiskSyncCandidate(
        _ candidate: DiskSyncCandidate?,
        markStartupRepairComplete: Bool = false
    ) -> [AIAcceptedLearningSummaryReadyEvent] {
        guard let candidate else {
            return []
        }
        let reloadedRecords = candidate.reloadedRecords
        let finalMetadata = candidate.finalMetadata
        let markerModifiedAt = candidate.markerModifiedAt
        let generatedAt = Date()
        let reloadedSummary = Self.buildSummary(records: reloadedRecords, generatedAt: generatedAt)
        let reloadedSchemaSummaries = Self.buildSchemaSummaries(records: reloadedRecords, generatedAt: generatedAt)
        lock.lock()
        let previousRecords = records
        let previousSchemaSummaries = schemaSummaries
        var changedSchemaIDs = pendingSummarySchemaIDs
        let allSchemas = Set(previousRecords.map(\.schemaID))
            .union(reloadedRecords.map(\.schemaID))
            .union(previousSchemaSummaries.keys)
            .union(reloadedSchemaSummaries.keys)
        for schemaID in allSchemas {
            let previousSchemaRecords = previousRecords.filter { $0.schemaID == schemaID }
            let reloadedSchemaRecords = reloadedRecords.filter { $0.schemaID == schemaID }
            if previousSchemaRecords != reloadedSchemaRecords
                || previousSchemaSummaries[schemaID]?.historyHash != reloadedSchemaSummaries[schemaID]?.historyHash
                || previousSchemaSummaries[schemaID]?.acceptedCount != reloadedSchemaSummaries[schemaID]?.acceptedCount {
                changedSchemaIDs.insert(schemaID)
            }
        }
        records = reloadedRecords
        summary = reloadedSummary
        schemaSummaries = reloadedSchemaSummaries
        pendingSummarySchemaIDs.removeAll()
        if let updatedMarkerDate = finalMetadata?.clearMarker.modificationDate ?? markerModifiedAt {
            lastClearMarkerModifiedAt = updatedMarkerDate
        }
        if markStartupRepairComplete {
            pendingStartupRepair = false
            pendingStartupSummaryWrite = false
            lastStartupRepairAttemptAt = nil
            lastFailedRepairEnvironmentStamp = nil
        }
        if let finalMetadata {
            lastDiskStateMetadata = finalMetadata
        }
        lock.unlock()
        return Self.summaryReadyEvents(
            from: reloadedSchemaSummaries,
            changedSchemaIDs: changedSchemaIDs
        )
    }

    private func retryPendingStartupRepair() throws -> [AIAcceptedLearningSummaryReadyEvent] {
        lock.lock()
        let hasCachedDiskMetadata = lastDiskStateMetadata != nil
        let forceSummaryFileRepair = pendingStartupSummaryWrite
        lock.unlock()

        let repairedState: StartupState
        if hasCachedDiskMetadata {
            repairedState = try withAcceptedLearningFileLock(
                lockURL: acceptedLearningLockURL(historyURL: historyURL),
                fileManager: fileManager
            ) {
                try Self.loadStartupState(
                    historyURL: historyURL,
                    summaryURL: summaryURL,
                    mirrorURL: mirrorURL,
                    fileManager: fileManager,
                    encoder: encoder,
                    decoder: decoder,
                    maxRecordCount: maxRecordCount,
                    compactPersistentHistory: true,
                    repairPersistentSummary: true,
                    forceSummaryFileRepair: forceSummaryFileRepair
                )
            }
        } else {
            let initialState = try withExistingAcceptedLearningFileLock(
                lockURL: acceptedLearningLockURL(historyURL: historyURL),
                fileManager: fileManager
            ) {
                try Self.loadStartupState(
                    historyURL: historyURL,
                    summaryURL: summaryURL,
                    mirrorURL: mirrorURL,
                    fileManager: fileManager,
                    encoder: encoder,
                    decoder: decoder,
                    maxRecordCount: maxRecordCount,
                    compactPersistentHistory: false,
                    repairPersistentSummary: false,
                    forceSummaryFileRepair: forceSummaryFileRepair
                )
            }
            if (initialState.needsCompaction && historyURL != nil)
                || initialState.needsSummaryFileRepair
                || initialState.needsMirrorRefresh
            {
                repairedState = try withAcceptedLearningFileLock(
                    lockURL: acceptedLearningLockURL(historyURL: historyURL),
                    fileManager: fileManager
                ) {
                    try Self.loadStartupState(
                        historyURL: historyURL,
                        summaryURL: summaryURL,
                        mirrorURL: mirrorURL,
                        fileManager: fileManager,
                        encoder: encoder,
                        decoder: decoder,
                        maxRecordCount: maxRecordCount,
                        compactPersistentHistory: true,
                        repairPersistentSummary: true,
                        forceSummaryFileRepair: forceSummaryFileRepair
                            || (initialState.needsCompaction && historyURL != nil)
                    )
                }
            } else {
                repairedState = initialState
            }
        }
        if repairedState.didCompactHistoryOnDisk {
            synchronizePeerAcceptedLearningStores(for: historyURL, excluding: self)
        }
        if let repairError = repairedState.repairError {
            let partialEvents = applyDiskSyncCandidate(
                DiskSyncCandidate(
                    reloadedRecords: repairedState.records,
                    finalMetadata: repairedState.lastDiskStateMetadata,
                    markerModifiedAt: repairedState.lastClearMarkerModifiedAt
                ),
                markStartupRepairComplete: false
            )
            lock.lock()
            pendingStartupSummaryWrite = repairedState.needsSummaryFileRepair
                || (repairedState.needsCompaction && historyURL != nil)
            lock.unlock()
            notifySummaryReady(partialEvents)
            throw repairError
        }
        return applyDiskSyncCandidate(
            DiskSyncCandidate(
                reloadedRecords: repairedState.records,
                finalMetadata: repairedState.lastDiskStateMetadata,
                markerModifiedAt: repairedState.lastClearMarkerModifiedAt
            ),
            markStartupRepairComplete: true
        )
    }

    @discardableResult
    private func syncRecordsAfterExternalClearLocked() throws -> [AIAcceptedLearningSummaryReadyEvent] {
        let candidate = try loadDiskSyncCandidate()
        return applyDiskSyncCandidate(candidate)
    }

    fileprivate func synchronizeWithDiskState() {
        syncRecordsAfterExternalClear()
    }

    private func syncRecordsAfterExternalClear() {
        lock.lock()
        let needsStartupRepair = pendingStartupRepair && !(isSummaryRebuildScheduled && lastDiskStateMetadata != nil)
        lock.unlock()
        if needsStartupRepair {
            let now = Date()
            let currentStamp = Self.repairEnvironmentStamp(
                historyURL: historyURL,
                summaryURL: summaryURL,
                mirrorURL: mirrorURL,
                fileManager: fileManager
            )
            lock.lock()
            let shouldRetryRepair = pendingStartupRepair
                && !(isSummaryRebuildScheduled && lastDiskStateMetadata != nil)
                && (lastFailedRepairEnvironmentStamp == nil
                    || currentStamp != lastFailedRepairEnvironmentStamp
                    || now.timeIntervalSince(lastStartupRepairAttemptAt ?? .distantPast) >= Self.startupRepairRetryInterval)
            if shouldRetryRepair {
                lastStartupRepairAttemptAt = now
            }
            let shouldSkipUnreadFallback = !shouldRetryRepair
                && lastDiskStateMetadata == nil
                && currentStamp == lastFailedRepairEnvironmentStamp
            lock.unlock()
            if shouldRetryRepair {
                do {
                    let repairedEvents = try retryPendingStartupRepair()
                    notifySummaryReady(repairedEvents)
                    return
                } catch {
                    let failedStamp = Self.repairEnvironmentStamp(
                        historyURL: historyURL,
                        summaryURL: summaryURL,
                        mirrorURL: mirrorURL,
                        fileManager: fileManager
                    )
                    lock.lock()
                    lastStartupRepairAttemptAt = Date()
                    lastFailedRepairEnvironmentStamp = failedStamp
                    let skipUnreadFallbackAfterFailure = lastDiskStateMetadata == nil
                    lock.unlock()
                    diagnosticSink.record(
                        AIRecommendationDiagnosticEvent(
                            stage: .lexicalProfileFallback,
                            reason: "accepted_learning_summary_repair_failed:\(String(describing: type(of: error)))"
                        )
                    )
                    if skipUnreadFallbackAfterFailure {
                        return
                    }
                }
            } else if shouldSkipUnreadFallback {
                return
            }
        }
        let events: [AIAcceptedLearningSummaryReadyEvent]
        do {
            events = try withExistingAcceptedLearningFileLock(
                lockURL: acceptedLearningLockURL(historyURL: historyURL),
                fileManager: fileManager,
                {
                    try loadDiskSyncCandidate()
                },
                commit: { candidate in
                    applyDiskSyncCandidate(candidate)
                }
            )
        } catch {
            diagnosticSink.record(
                AIRecommendationDiagnosticEvent(
                    stage: .lexicalProfileFallback,
                    reason: "accepted_learning_clear_sync_failed:\(String(describing: type(of: error)))"
                )
            )
            return
        }
        notifySummaryReady(events)
    }

    private func notifySummaryReady(_ events: [AIAcceptedLearningSummaryReadyEvent]) {
        guard !events.isEmpty else {
            return
        }
        lock.lock()
        let observers = Array(summaryObservers.values)
        lock.unlock()
        guard !observers.isEmpty else {
            return
        }
        for event in events {
            for observer in observers {
                observer(event)
            }
        }
    }

    public static func buildSummary(
        records: [AIAcceptedLearningRecord],
        generatedAt: Date
    ) -> AIAcceptedLanguageSummary? {
        guard !records.isEmpty else {
            return nil
        }

        var termScores: [String: (score: Double, source: String)] = [:]
        for record in records {
            guard !TextProtection.requiresNoCorrection(record.acceptedText) else {
                continue
            }
            for term in record.extractedTerms {
                guard let clean = LexicalContextBuilder.sanitizedAcceptedProfileText(term.text) else {
                    continue
                }
                let nextScore = min(1, max(0, term.score))
                if let existing = termScores[clean] {
                    termScores[clean] = (
                        score: min(1, existing.score + nextScore * 0.18),
                        source: existing.source
                    )
                } else {
                    termScores[clean] = (score: nextScore, source: "accepted-ai")
                }
            }
        }

        let terms = termScores
            .map { text, value in
                LexicalContextTerm(text: text, score: value.score, source: value.source)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.text < rhs.text
                }
                return lhs.score > rhs.score
            }
            .prefix(32)
            .map { $0 }

        let recentCommits = records
            .suffix(16)
            .compactMap { boundedCommit($0.acceptedText) }
            .suffix(8)

        let style = LexicalContextBuilder().acceptedStyleProfile(from: Array(recentCommits))
        let historyHash = Self.historyHash(records)
        return AIAcceptedLanguageSummary(
            generatedAt: generatedAt,
            historyHash: historyHash,
            acceptedCount: records.count,
            termProfile: terms,
            styleProfile: style,
            recentAcceptedCommits: Array(recentCommits),
            sourceSummary: [
                "accepted-ai-summary: terms=\(terms.count) commits=\(recentCommits.count) history=\(String(historyHash.prefix(8)))"
            ]
        )
    }

    private static func buildSchemaSummaries(
        records: [AIAcceptedLearningRecord],
        generatedAt: Date
    ) -> [String: AIAcceptedLanguageSummary] {
        Dictionary(
            uniqueKeysWithValues: Dictionary(grouping: records, by: \.schemaID).compactMap { schemaID, schemaRecords in
                guard let summary = buildSummary(records: schemaRecords, generatedAt: generatedAt) else {
                    return nil
                }
                return (schemaID, summary)
            }
        )
    }

    private static func summaryReadyEvents(
        from schemaSummaries: [String: AIAcceptedLanguageSummary],
        changedSchemaIDs: Set<String>
    ) -> [AIAcceptedLearningSummaryReadyEvent] {
        changedSchemaIDs.sorted().map { schemaID in
            if let summary = schemaSummaries[schemaID] {
                return AIAcceptedLearningSummaryReadyEvent(
                    schemaID: schemaID,
                    historyHash: summary.historyHash,
                    acceptedCount: summary.acceptedCount,
                    termCount: summary.termProfile.count,
                    recentCommitCount: summary.recentAcceptedCommits.count
                )
            }
            return AIAcceptedLearningSummaryReadyEvent(
                schemaID: schemaID,
                historyHash: "",
                acceptedCount: 0,
                termCount: 0,
                recentCommitCount: 0
            )
        }
    }

    private static func summary(
        _ summary: AIAcceptedLanguageSummary?,
        matches records: [AIAcceptedLearningRecord]
    ) -> Bool {
        guard let rebuilt = buildSummary(records: records, generatedAt: Date()) else {
            return summary == nil
        }
        guard let summary else {
            return false
        }
        return summary.acceptedCount == records.count
            && summary.historyHash == rebuilt.historyHash
    }

    private static func boundedCommit(_ text: String) -> String? {
        let clean = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !clean.isEmpty,
              !TextProtection.containsSecretLikeContent(clean),
              !TextProtection.requiresNoCorrection(clean) else {
            return nil
        }
        if clean.count <= 48 {
            return clean
        }
        return String(clean.prefix(48)) + "..."
    }

    public static func historyHash(_ records: [AIAcceptedLearningRecord]) -> String {
        let joined = records.map(\.textHash).joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func renderMarkdown(
        _ summary: AIAcceptedLanguageSummary,
        maxRecordCount: Int = defaultMaxRecordCount
    ) -> String {
        let clampedMaxRecordCount = max(1, maxRecordCount)
        let recordCountDescription = clampedMaxRecordCount == 1
            ? "1 record"
            : "\(clampedMaxRecordCount) records"
        var lines: [String] = [
            "# KnowType Accepted AI Learning",
            "",
            "This is a local summary of AI recommendations the user explicitly accepted. Retained history (a sliding window of the latest \(recordCountDescription), plus a bounded ledger of up to 4,096 SHA-256 digests for evicted commits in accepted-ai-learning.evicted-commits.json that may temporarily include active-record digests if a clear retry is pending) stays local and is not injected into provider requests.",
            "",
            "## Stats",
            "- Accepted count: \(summary.acceptedCount)",
            "- History hash: \(summary.historyHash)",
            "- Generated at: \(ISO8601DateFormatter().string(from: summary.generatedAt))",
            "",
            "## Style",
            "- Register: \(summary.styleProfile.register)",
            "- Technical density: \(String(format: "%.2f", summary.styleProfile.technicalDensity))",
            "- Code switching ratio: \(String(format: "%.2f", summary.styleProfile.codeSwitchingRatio))",
            "- Punctuation style: \(summary.styleProfile.punctuationStyle)"
        ]
        if !summary.styleProfile.connectors.isEmpty {
            lines.append("- Connectors: \(summary.styleProfile.connectors.joined(separator: ", "))")
        }
        if !summary.styleProfile.endings.isEmpty {
            lines.append("- Common endings: \(summary.styleProfile.endings.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("## Accepted Terms")
        if summary.termProfile.isEmpty {
            lines.append("- No accepted AI terms yet.")
        } else {
            for term in summary.termProfile {
                lines.append("- \(term.text) [\(term.source), \(String(format: "%.2f", term.score))]")
            }
        }
        lines.append("")
        lines.append("## Recent Accepted Commits")
        if summary.recentAcceptedCommits.isEmpty {
            lines.append("- No recent accepted AI commits yet.")
        } else {
            summary.recentAcceptedCommits.forEach { lines.append("- \($0)") }
        }
        lines.append("")
        lines.append("## Sources")
        summary.sourceSummary.forEach { lines.append("- \($0)") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func loadRecordsOrThrow(
        from url: URL?,
        decoder: JSONDecoder,
        fileManager: FileManager = .default
    ) throws -> [AIAcceptedLearningRecord] {
        guard let url else {
            return []
        }
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            if isAcceptedLearningNoSuchFileError(error) || !fileManager.fileExists(atPath: url.path) {
                return []
            }
            throw error
        }
        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(AIAcceptedLearningRecord.self, from: data)
            }
    }

    private static func loadRecords(
        from url: URL?,
        decoder: JSONDecoder
    ) -> [AIAcceptedLearningRecord] {
        (try? loadRecordsOrThrow(from: url, decoder: decoder)) ?? []
    }

    private static func loadRecordsWithMetadata(
        from historyURL: URL?,
        decoder: JSONDecoder,
        fileManager: FileManager
    ) throws -> (records: [AIAcceptedLearningRecord], metadata: DiskStateMetadata?) {
        guard let historyURL else {
            return ([], nil)
        }
        for _ in 0..<3 {
            let before = diskStateMetadata(historyURL: historyURL, fileManager: fileManager)
            let records = try loadRecordsOrThrow(
                from: historyURL,
                decoder: decoder,
                fileManager: fileManager
            )
            let after = diskStateMetadata(historyURL: historyURL, fileManager: fileManager)
            if before == after {
                return (records, before)
            }
        }
        let fallbackRecords = try loadRecordsOrThrow(
            from: historyURL,
            decoder: decoder,
            fileManager: fileManager
        )
        return (fallbackRecords, nil)
    }

    private static func loadSummary(
        from url: URL?,
        decoder: JSONDecoder
    ) -> AIAcceptedLanguageSummary? {
        guard let url,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(AIAcceptedLanguageSummary.self, from: data)
    }

    private static func loadStartupState(
        historyURL: URL?,
        summaryURL: URL?,
        mirrorURL: URL?,
        fileManager: FileManager,
        encoder: JSONEncoder,
        decoder: JSONDecoder,
        maxRecordCount: Int,
        compactPersistentHistory: Bool,
        repairPersistentSummary: Bool,
        forceSummaryFileRepair: Bool = false
    ) throws -> StartupState {
        let loaded = try Self.loadRecordsWithMetadata(
            from: historyURL,
            decoder: decoder,
            fileManager: fileManager
        )
        let loadedRecords = loaded.records
        var diskMetadata = loaded.metadata
        let needsCompaction = loadedRecords.count > maxRecordCount
        var didCompactHistoryOnDisk = false
        var repairError: (any Error)?
        let records: [AIAcceptedLearningRecord]
        if needsCompaction {
            let overflowCount = loadedRecords.count - maxRecordCount
            let evictedRecords = Array(loadedRecords.prefix(overflowCount))
            records = Array(loadedRecords.suffix(maxRecordCount))
            if compactPersistentHistory, let historyURL {
                do {
                    try recordAcceptedLearningEvictedCommits(
                        evictedRecords,
                        historyURL: historyURL,
                        fileManager: fileManager
                    )
                    try Self.writeRecords(
                        records,
                        to: historyURL,
                        encoder: encoder,
                        fileManager: fileManager
                    )
                    didCompactHistoryOnDisk = true
                    diskMetadata = Self.diskStateMetadata(
                        historyURL: historyURL,
                        fileManager: fileManager
                    )
                } catch {
                    repairError = error
                }
            }
        } else {
            records = loadedRecords
        }
        let loadedSummary = Self.loadSummary(from: summaryURL, decoder: decoder)
        let rebuiltSummary = Self.buildSummary(records: records, generatedAt: Date())
        let summaryFileExists = summaryURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let summaryMatchesRecords = !needsCompaction
            && Self.summary(loadedSummary, matches: records)
            && (!summaryFileExists || loadedSummary != nil)
        let nextSummary = summaryMatchesRecords ? loadedSummary : rebuiltSummary
        let shouldRepairSummaryFile = (needsCompaction || forceSummaryFileRepair) && summaryURL != nil
        var needsSummaryFileRepair = shouldRepairSummaryFile && !summaryMatchesRecords
        let mirrorFileExists = mirrorURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let mirrorIsCurrent: Bool
        if mirrorURL == nil {
            mirrorIsCurrent = true
        } else if !mirrorFileExists {
            mirrorIsCurrent = !(needsCompaction || forceSummaryFileRepair) || nextSummary == nil
        } else if let nextSummary,
                  let loadedMirror = mirrorURL.flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) {
            mirrorIsCurrent = loadedMirror == Self.renderMarkdown(nextSummary, maxRecordCount: maxRecordCount)
        } else {
            mirrorIsCurrent = false
        }
        var needsMirrorRefresh = !mirrorIsCurrent
        if repairPersistentSummary, repairError == nil, (needsSummaryFileRepair || needsMirrorRefresh) {
            do {
                if needsSummaryFileRepair {
                    if let nextSummary {
                        if let summaryURL {
                            try atomicWrite(try encoder.encode(nextSummary), to: summaryURL, fileManager: fileManager)
                        }
                    } else if let summaryURL, fileManager.fileExists(atPath: summaryURL.path) {
                        try fileManager.removeItem(at: summaryURL)
                    }
                    needsSummaryFileRepair = false
                }
                if needsMirrorRefresh {
                    try persistMirror(
                        nextSummary,
                        mirrorURL: mirrorURL,
                        fileManager: fileManager,
                        maxRecordCount: maxRecordCount
                    )
                    needsMirrorRefresh = false
                }
            } catch {
                repairError = error
            }
        }
        return StartupState(
            records: records,
            summary: nextSummary,
            schemaSummaries: Self.buildSchemaSummaries(records: records, generatedAt: Date()),
            lastClearMarkerModifiedAt: diskMetadata?.clearMarker.modificationDate,
            lastDiskStateMetadata: diskMetadata,
            needsCompaction: needsCompaction && !didCompactHistoryOnDisk,
            needsSummaryFileRepair: needsSummaryFileRepair,
            needsMirrorRefresh: needsMirrorRefresh,
            didCompactHistoryOnDisk: didCompactHistoryOnDisk,
            repairError: repairError
        )
    }

    private static func fileMetadataStamp(
        _ url: URL?,
        fileManager: FileManager
    ) -> FileMetadataStamp {
        guard let url,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return FileMetadataStamp(
                exists: false,
                fileNumber: nil,
                size: nil,
                modificationDate: nil,
                permissions: nil
            )
        }
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let size = (attributes[.size] as? NSNumber)?.uint64Value
        let modificationDate = attributes[.modificationDate] as? Date
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
        return FileMetadataStamp(
            exists: true,
            fileNumber: fileNumber,
            size: size,
            modificationDate: modificationDate,
            permissions: permissions
        )
    }

    private static func repairEnvironmentStamp(
        historyURL: URL?,
        summaryURL: URL?,
        mirrorURL: URL?,
        fileManager: FileManager
    ) -> RepairEnvironmentStamp {
        RepairEnvironmentStamp(
            directory: fileMetadataStamp(historyURL?.deletingLastPathComponent(), fileManager: fileManager),
            summaryDirectory: fileMetadataStamp(summaryURL?.deletingLastPathComponent(), fileManager: fileManager),
            mirrorDirectory: fileMetadataStamp(mirrorURL?.deletingLastPathComponent(), fileManager: fileManager),
            history: fileMetadataStamp(historyURL, fileManager: fileManager),
            summary: fileMetadataStamp(summaryURL, fileManager: fileManager),
            mirror: fileMetadataStamp(mirrorURL, fileManager: fileManager),
            evictedCommits: fileMetadataStamp(
                acceptedLearningEvictedCommitsURL(historyURL: historyURL),
                fileManager: fileManager
            )
        )
    }

    private static func diskStateMetadata(
        historyURL: URL?,
        fileManager: FileManager
    ) -> DiskStateMetadata? {
        guard let historyURL else {
            return nil
        }
        return DiskStateMetadata(
            history: fileMetadataStamp(historyURL, fileManager: fileManager),
            clearMarker: fileMetadataStamp(
                acceptedLearningClearMarkerURL(historyURL: historyURL),
                fileManager: fileManager
            ),
            evictedCommits: fileMetadataStamp(
                acceptedLearningEvictedCommitsURL(historyURL: historyURL),
                fileManager: fileManager
            )
        )
    }

    private static func fileModificationDate(_ url: URL?, fileManager: FileManager) -> Date? {
        guard let url,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private static func writeRecords(
        _ records: [AIAcceptedLearningRecord],
        to url: URL,
        encoder: JSONEncoder,
        fileManager: FileManager
    ) throws {
        var buffer = Data()
        for record in records {
            let data = try encoder.encode(record)
            buffer.append(data)
            buffer.append(0x0A)
        }
        try atomicWrite(buffer, to: url, fileManager: fileManager)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try Self.atomicWrite(data, to: url, fileManager: fileManager)
    }

    private static func atomicWrite(_ data: Data, to url: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func persistSummary(_ summary: AIAcceptedLanguageSummary?) throws {
        try Self.persistSummary(
            summary,
            summaryURL: summaryURL,
            mirrorURL: mirrorURL,
            encoder: encoder,
            fileManager: fileManager,
            maxRecordCount: maxRecordCount
        )
    }

    private static func persistSummary(
        _ summary: AIAcceptedLanguageSummary?,
        summaryURL: URL?,
        mirrorURL: URL?,
        encoder: JSONEncoder,
        fileManager: FileManager,
        maxRecordCount: Int
    ) throws {
        if let summary {
            if let summaryURL {
                try atomicWrite(try encoder.encode(summary), to: summaryURL, fileManager: fileManager)
            }
            try persistMirror(
                summary,
                mirrorURL: mirrorURL,
                fileManager: fileManager,
                maxRecordCount: maxRecordCount
            )
            return
        }
        if let summaryURL,
           fileManager.fileExists(atPath: summaryURL.path) {
            try fileManager.removeItem(at: summaryURL)
        }
        try persistMirror(
            nil,
            mirrorURL: mirrorURL,
            fileManager: fileManager,
            maxRecordCount: maxRecordCount
        )
    }

    private static func persistMirror(
        _ summary: AIAcceptedLanguageSummary?,
        mirrorURL: URL?,
        fileManager: FileManager,
        maxRecordCount: Int
    ) throws {
        guard let mirrorURL else {
            return
        }
        if let summary {
            try atomicWrite(
                Data(Self.renderMarkdown(summary, maxRecordCount: maxRecordCount).utf8),
                to: mirrorURL,
                fileManager: fileManager
            )
            return
        }
        if fileManager.fileExists(atPath: mirrorURL.path) {
            try fileManager.removeItem(at: mirrorURL)
        }
    }

    private static func defaultApplicationSupportAIDirectory(fileManager: FileManager) -> URL {
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return root
            .appendingPathComponent("KnowType", isDirectory: true)
            .appendingPathComponent("AI", isDirectory: true)
    }
}
