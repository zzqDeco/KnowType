import CryptoKit
import Foundation

public struct AIUserDirectory: Sendable, Equatable {
    public var rootURL: URL

    public init(rootURL: URL) { self.rootURL = rootURL }

    public static func defaultDirectory(fileManager: FileManager = .default) -> AIUserDirectory {
        AIUserDirectory(rootURL: fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".knowtype", isDirectory: true))
    }

    public var environmentURL: URL { rootURL.appendingPathComponent("ENV.md") }
    public var correctionInstructionURL: URL { rootURL.appendingPathComponent("CORRECTION.md") }
    public var eventsDirectoryURL: URL { rootURL.appendingPathComponent("events", isDirectory: true) }
    public var lexicalProfileURL: URL { rootURL.appendingPathComponent("LEXICAL_PROFILE.md") }
    public var acceptedLearningMirrorURL: URL { rootURL.appendingPathComponent("ACCEPTED_AI_LEARNING.md") }
    public var acceptedFeedbackMirrorURL: URL { rootURL.appendingPathComponent("ACCEPTED_AI_FEEDBACK.md") }
    public var environmentBackupsDirectoryURL: URL { rootURL.appendingPathComponent("backups", isDirectory: true) }
    public var environmentDigestClaimURL: URL { rootURL.appendingPathComponent("ENV.digest-claim.json") }
    public var environmentDigestScheduleURL: URL { rootURL.appendingPathComponent("ENV.digest-schedule.json") }
    public var environmentDigestArchiveReceiptURL: URL { rootURL.appendingPathComponent("ENV.digest-archive-receipt.json") }
}

public struct AIDocumentSnapshot: Sendable, Equatable {
    public var content: String
    public var sha256: String

    public init(content: String) {
        self.content = content
        self.sha256 = Self.hash(content)
    }

    static func hash(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct EnvironmentDigestClaim: Codable, Sendable, Equatable {
    public var claimedPrefixSHA256: String
    public var claimedPrefixByteCount: Int
    public var claimedEventCount: Int
    public var generatedSHA256: String
    public var providerGeneration: UInt64

    public init(
        claimedPrefixSHA256: String,
        claimedPrefixByteCount: Int,
        claimedEventCount: Int,
        generatedSHA256: String,
        providerGeneration: UInt64
    ) {
        self.claimedPrefixSHA256 = claimedPrefixSHA256
        self.claimedPrefixByteCount = claimedPrefixByteCount
        self.claimedEventCount = claimedEventCount
        self.generatedSHA256 = generatedSHA256
        self.providerGeneration = providerGeneration
    }
}

public struct EnvironmentDigestScheduleState: Codable, Sendable, Equatable {
    public var pendingSince: Date?
    public var lastSuccessfulDigestAt: Date?
    public var nextEligibleAt: Date?
    public var pendingEventCount: Int

    public init(
        pendingSince: Date?,
        lastSuccessfulDigestAt: Date?,
        nextEligibleAt: Date?,
        pendingEventCount: Int
    ) {
        self.pendingSince = pendingSince
        self.lastSuccessfulDigestAt = lastSuccessfulDigestAt
        self.nextEligibleAt = nextEligibleAt
        self.pendingEventCount = pendingEventCount
    }
}

public struct EnvironmentDigestArchiveReceipt: Codable, Sendable, Equatable {
    public var claimedPrefixSHA256: String
    public var claimedPrefixByteCount: Int
    public var claimedEventCount: Int
    public var generatedSHA256: String
    public var archivedByteCount: Int

    public init(
        claimedPrefixSHA256: String,
        claimedPrefixByteCount: Int,
        claimedEventCount: Int,
        generatedSHA256: String,
        archivedByteCount: Int
    ) {
        self.claimedPrefixSHA256 = claimedPrefixSHA256
        self.claimedPrefixByteCount = claimedPrefixByteCount
        self.claimedEventCount = claimedEventCount
        self.generatedSHA256 = generatedSHA256
        self.archivedByteCount = archivedByteCount
    }
}

public enum EnvironmentDocumentError: Error, Sendable, Equatable {
    case scanLimitExceeded
    case invalidUTF8
    case ambiguousMigration
    case invalidDigestCandidate
    case generatedSectionTooLarge
    case userNotesTooLarge
    case environmentProjectionTooLarge
    case claimMismatch
}

final class EnvironmentDocumentStoreTestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var failedClaimClearsRemaining = 0
    private var failedArchiveReceiptWritesRemaining = 0

    func failNextClaimClears(_ count: Int) {
        lock.lock()
        failedClaimClearsRemaining = max(0, count)
        lock.unlock()
    }

    func failNextArchiveReceiptWrites(_ count: Int) {
        lock.lock()
        failedArchiveReceiptWritesRemaining = max(0, count)
        lock.unlock()
    }

    fileprivate func shouldFailClaimClear() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failedClaimClearsRemaining > 0 else { return false }
        failedClaimClearsRemaining -= 1
        return true
    }

    fileprivate func shouldFailArchiveReceiptWrite() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failedArchiveReceiptWritesRemaining > 0 else { return false }
        failedArchiveReceiptWritesRemaining -= 1
        return true
    }
}

public struct EnvironmentDocumentStore: @unchecked Sendable {
    public static let generatedStart = "<!-- KNOWTYPE:BEGIN GENERATED -->"
    public static let generatedEnd = "<!-- KNOWTYPE:END GENERATED -->"
    public static let documentTitle = "# KnowType Environment"
    public static let userNotesTitle = "## User Notes"
    public static let maximumScanByteCount = 1 * 1_024 * 1_024

    public static let defaultContent = """
    # KnowType Environment

    <!-- KNOWTYPE:BEGIN GENERATED -->
    ## Global Style
    - No stable preference has been learned yet.

    ## App Habits
    - No app-specific habits have been learned yet.

    ## Recent Work Context
    - No recent work context has been summarized yet.
    <!-- KNOWTYPE:END GENERATED -->

    ## User Notes
    """

    private let fileURL: URL
    private let fileManager: FileManager
    private let testProbe: EnvironmentDocumentStoreTestProbe?

    public init(fileURL: URL = AIUserDirectory.defaultDirectory().environmentURL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.testProbe = nil
    }

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        testProbe: EnvironmentDocumentStoreTestProbe?
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.testProbe = testProbe
    }

    public func loadSnapshot() throws -> AIDocumentSnapshot {
        try ensureExists(defaultContent: Self.defaultContent)
        let data = try boundedData(at: fileURL)
        try setSecurePermissions(of: fileURL)
        guard let content = String(data: data, encoding: .utf8) else {
            try backup(data: data)
            throw EnvironmentDocumentError.invalidUTF8
        }
        do {
            let result = try Self.canonicalize(content)
            if result.content != content {
                if result.requiresBackup { try backup(data: data) }
                try atomicWrite(result.content, to: fileURL)
            }
            return AIDocumentSnapshot(content: result.content)
        } catch {
            try? backup(data: data)
            throw error
        }
    }

    public func replaceGeneratedSection(with generatedMarkdown: String) throws -> AIDocumentSnapshot {
        try Self.validateGeneratedMarkdown(generatedMarkdown)
        let current = try loadSnapshot().content
        let next = try Self.canonicalDocument(generated: generatedMarkdown, current: current)
        try atomicWrite(next, to: fileURL)
        return AIDocumentSnapshot(content: next)
    }

    public func loadDigestClaim() throws -> EnvironmentDigestClaim? {
        guard fileManager.fileExists(atPath: claimURL.path) else { return nil }
        try setSecurePermissions(of: claimURL)
        let data = try boundedData(at: claimURL, limit: 32 * 1_024)
        return try JSONDecoder().decode(EnvironmentDigestClaim.self, from: data)
    }

    public func saveDigestClaim(_ claim: EnvironmentDigestClaim) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(claim)
        try atomicWrite(data: data, to: claimURL)
    }

    public func clearDigestClaim() throws {
        guard fileManager.fileExists(atPath: claimURL.path) else { return }
        if testProbe?.shouldFailClaimClear() == true {
            throw CocoaError(.fileWriteUnknown)
        }
        try fileManager.removeItem(at: claimURL)
    }

    public func loadDigestScheduleState() throws -> EnvironmentDigestScheduleState? {
        guard fileManager.fileExists(atPath: scheduleURL.path) else { return nil }
        try setSecurePermissions(of: scheduleURL)
        let data = try boundedData(at: scheduleURL, limit: 16 * 1_024)
        let state = try JSONDecoder().decode(EnvironmentDigestScheduleState.self, from: data)
        guard state.pendingEventCount >= 0, state.pendingEventCount <= 500 else {
            throw EnvironmentDocumentError.claimMismatch
        }
        return state
    }

    public func saveDigestScheduleState(_ state: EnvironmentDigestScheduleState) throws {
        guard state.pendingEventCount >= 0, state.pendingEventCount <= 500 else {
            throw EnvironmentDocumentError.claimMismatch
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try atomicWrite(data: encoder.encode(state), to: scheduleURL)
    }

    public func clearDigestScheduleState() throws {
        guard fileManager.fileExists(atPath: scheduleURL.path) else { return }
        try fileManager.removeItem(at: scheduleURL)
    }

    public func loadDigestArchiveReceipt() throws -> EnvironmentDigestArchiveReceipt? {
        guard fileManager.fileExists(atPath: archiveReceiptURL.path) else { return nil }
        try setSecurePermissions(of: archiveReceiptURL)
        let data = try boundedData(at: archiveReceiptURL, limit: 16 * 1_024)
        return try JSONDecoder().decode(EnvironmentDigestArchiveReceipt.self, from: data)
    }

    public func saveDigestArchiveReceipt(_ receipt: EnvironmentDigestArchiveReceipt) throws {
        if testProbe?.shouldFailArchiveReceiptWrite() == true {
            throw CocoaError(.fileWriteUnknown)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try atomicWrite(data: encoder.encode(receipt), to: archiveReceiptURL)
    }

    public func clearDigestArchiveReceipt() throws {
        guard fileManager.fileExists(atPath: archiveReceiptURL.path) else { return }
        try fileManager.removeItem(at: archiveReceiptURL)
    }

    public static func validateGeneratedMarkdown(_ candidate: String) throws {
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              Data(value.utf8).count <= 4 * 1_024,
              value.components(separatedBy: "\n").count <= 200 else {
            throw EnvironmentDocumentError.invalidDigestCandidate
        }
        let forbidden = [generatedStart, generatedEnd, documentTitle, userNotesTitle]
        guard forbidden.allSatisfy({ !value.contains($0) }) else {
            throw EnvironmentDocumentError.invalidDigestCandidate
        }
    }

    public static func generatedSection(from content: String) -> String? {
        let lines = content.components(separatedBy: "\n")
        guard let markers = structuredGeneratedMarkerIndices(in: lines) else { return nil }
        return lines[(markers.start + 1)..<markers.end]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func generatedSectionHash(from content: String) -> String? {
        generatedSection(from: content).map(AIDocumentSnapshot.hash)
    }

    public static func replacingGeneratedSection(in content: String, with generatedMarkdown: String) -> String {
        let repaired = repairingGeneratedSectionMarkers(in: content)
        let generated = generatedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = repaired.components(separatedBy: "\n")
        guard let markers = structuredGeneratedMarkerIndices(in: lines) else {
            let preserved = repaired.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(documentTitle)\n\n\(generatedStart)\n\(generated)\n\(generatedEnd)\n\n\(preserved)"
        }
        lines.replaceSubrange(
            (markers.start + 1)..<markers.end,
            with: generated.components(separatedBy: "\n")
        )
        return lines.joined(separator: "\n")
    }

    public static func repairingGeneratedSectionMarkers(in content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var repaired: [String] = []
        var index = 0
        var completedFirstSection = false
        var reachedUserNotes = false
        while index < lines.count {
            let line = lines[index]
            let marker = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !completedFirstSection {
                repaired.append(line)
                if marker == generatedStart {
                    index += 1
                    while index < lines.count {
                        let generatedLine = lines[index]
                        let generatedMarker = generatedLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        if generatedMarker == generatedEnd {
                            repaired.append(generatedLine)
                            completedFirstSection = true
                            break
                        } else if generatedMarker != generatedStart {
                            repaired.append(generatedLine)
                        }
                        index += 1
                    }
                }
                index += 1
                continue
            }
            if marker == userNotesTitle { reachedUserNotes = true }
            if !reachedUserNotes, marker == generatedStart,
               let duplicateEnd = matchingGeneratedEndIndex(in: lines, from: index + 1) {
                removeTrailingDuplicateEnvironmentHeader(from: &repaired)
                index = duplicateEnd + 1
                continue
            }
            repaired.append(line)
            index += 1
        }
        return completedFirstSection ? repaired.joined(separator: "\n") : content
    }

    private struct CanonicalResult {
        var content: String
        var requiresBackup: Bool
    }

    private static func canonicalize(_ content: String) throws -> CanonicalResult {
        let lines = content.components(separatedBy: "\n")
        let starts = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == generatedStart }
        let ends = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == generatedEnd }
        let notes = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == userNotesTitle }
        let isMarkerless = starts.isEmpty && ends.isEmpty
        let firstNotesIndex = notes.first
        let titles = lines.indices.filter { index in
            let isStructural = firstNotesIndex.map { index < $0 } ?? true
            return isStructural && lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == documentTitle
        }.count
        if !isMarkerless, notes.count > 1 {
            throw EnvironmentDocumentError.ambiguousMigration
        }

        let hasValidPair = starts.count == 1 && ends.count == 1 && starts[0] < ends[0]
        let noteBody: String
        if isMarkerless {
            noteBody = markerlessUserNotesBody(in: content)
        } else if hasValidPair, notes.isEmpty {
            noteBody = userTextOutsideGeneratedPair(
                in: lines,
                startIndex: starts[0],
                endIndex: ends[0]
            )
        } else if let noteIndex = notes.first {
            noteBody = bodyAfterHeading(in: content, lineIndex: noteIndex)
        } else {
            noteBody = ""
        }
        try validateUserNotes(noteBody)

        let generated: String
        var requiresBackup = false
        if hasValidPair {
            let existing = lines[(starts[0] + 1)..<ends[0]]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if (try? validateGeneratedMarkdown(existing)) != nil && titles <= 1 {
                generated = existing
            } else {
                generated = defaultGeneratedMarkdown
                requiresBackup = true
            }
        } else if starts.isEmpty && ends.isEmpty {
            generated = defaultGeneratedMarkdown
        } else if starts.count == ends.count, starts.count > 1, notes.count == 1 {
            generated = defaultGeneratedMarkdown
            requiresBackup = true
        } else {
            throw EnvironmentDocumentError.ambiguousMigration
        }

        let canonical = try canonicalDocument(generated: generated, userNotes: noteBody)
        return CanonicalResult(content: canonical, requiresBackup: requiresBackup)
    }

    private static var defaultGeneratedMarkdown: String {
        let start = defaultContent.range(of: generatedStart)!
        let end = defaultContent.range(of: generatedEnd, range: start.upperBound..<defaultContent.endIndex)!
        return String(defaultContent[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalDocument(generated: String, current: String) throws -> String {
        let notes = current.range(of: userNotesTitle).map { bodyAfterHeading(in: current, headingRange: $0) } ?? current
        return try canonicalDocument(generated: generated, userNotes: notes)
    }

    private static func canonicalDocument(generated: String, userNotes: String) throws -> String {
        try validateGeneratedMarkdown(generated)
        try validateUserNotes(userNotes)
        var result = "\(documentTitle)\n\n\(generatedStart)\n\(generated)\n\(generatedEnd)\n\n\(userNotesTitle)"
        if !userNotes.isEmpty { result += "\n\(userNotes)" }
        guard Data(result.utf8).count <= 8 * 1_024 else { throw EnvironmentDocumentError.environmentProjectionTooLarge }
        return result
    }

    private static func validateUserNotes(_ notes: String) throws {
        guard Data(notes.utf8).count <= 4 * 1_024 else { throw EnvironmentDocumentError.userNotesTooLarge }
    }

    private static func markerlessUserNotesBody(in content: String) -> String {
        content
            .components(separatedBy: "\n")
            .filter {
                let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return line != userNotesTitle
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func userTextOutsideGeneratedPair(
        in lines: [String],
        startIndex: Int,
        endIndex: Int
    ) -> String {
        let prefix = Array(lines[..<startIndex])
        let suffix = endIndex + 1 < lines.count ? Array(lines[(endIndex + 1)...]) : []
        return (prefix + suffix)
            .filter {
                let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return line != documentTitle && line != userNotesTitle
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func structuredGeneratedMarkerIndices(in lines: [String]) -> (start: Int, end: Int)? {
        let starts = lines.indices.filter {
            lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == generatedStart
        }
        let ends = lines.indices.filter {
            lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == generatedEnd
        }
        guard starts.count == 1, ends.count == 1, starts[0] < ends[0] else { return nil }
        return (starts[0], ends[0])
    }

    private static func bodyAfterHeading(in content: String, lineIndex: Int) -> String {
        let lines = content.components(separatedBy: "\n")
        let prefix = lines.prefix(lineIndex + 1).joined(separator: "\n")
        guard let range = content.range(of: prefix) else { return "" }
        let suffix = content[range.upperBound...]
        return suffix.first == "\n" ? String(suffix.dropFirst()) : String(suffix)
    }

    private static func bodyAfterHeading(in content: String, headingRange: Range<String.Index>) -> String {
        let suffix = content[headingRange.upperBound...]
        return suffix.first == "\n" ? String(suffix.dropFirst()) : String(suffix)
    }

    private static func matchingGeneratedEndIndex(in lines: [String], from startIndex: Int) -> Int? {
        var index = startIndex
        while index < lines.count {
            let marker = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if marker == generatedEnd { return index }
            if marker == generatedStart { return nil }
            index += 1
        }
        return nil
    }

    private static func removeTrailingDuplicateEnvironmentHeader(from lines: inout [String]) {
        var cursor = lines.count
        while cursor > 0, lines[cursor - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { cursor -= 1 }
        guard cursor > 0, lines[cursor - 1].trimmingCharacters(in: .whitespacesAndNewlines) == documentTitle else { return }
        lines.removeSubrange((cursor - 1)..<lines.count)
    }

    private var claimURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("ENV.digest-claim.json") }
    private var scheduleURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("ENV.digest-schedule.json") }
    private var archiveReceiptURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("ENV.digest-archive-receipt.json") }

    private func ensureExists(defaultContent: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: fileURL.path) else { return }
        try atomicWrite(defaultContent, to: fileURL)
    }

    private func boundedData(at url: URL, limit: Int = maximumScanByteCount) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            let chunkSize = min(64 * 1_024, limit + 1 - data.count)
            guard chunkSize > 0 else { break }
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= limit else { throw EnvironmentDocumentError.scanLimitExceeded }
        return data
    }

    private func backup(data: Data) throws {
        let directory = fileURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let destination = directory.appendingPathComponent("ENV-\(digest).md")
        if fileManager.fileExists(atPath: destination.path) {
            try setSecurePermissions(of: destination)
            return
        }
        try atomicWrite(data: data, to: destination)
    }

    private func atomicWrite(_ content: String, to url: URL) throws { try atomicWrite(data: Data(content.utf8), to: url) }

    private func atomicWrite(data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try setSecurePermissions(of: temporaryURL)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
            try setSecurePermissions(of: url)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func setSecurePermissions(of url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public struct CorrectionInstructionStore: @unchecked Sendable {
    public static let defaultContent = """
    # KnowType Correction Instructions

    - 用户可能点到键盘临近键。
    - 用户可能少打一个或多个字符。
    - 用户可能多打一个或多个字符。
    - 保留技术词、变量名、URL、路径、命令、邮箱。
    - 不改写用户已经确认上屏的内容。
    """

    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = AIUserDirectory.defaultDirectory().correctionInstructionURL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadSnapshot() throws -> AIDocumentSnapshot {
        try ensureExists()
        try setSecurePermissions(of: fileURL)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let limit = 4 * 1_024
        var data = Data()
        while data.count <= limit {
            let chunk = try handle.read(upToCount: min(1_024, limit + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= 4 * 1_024,
              let content = String(data: data, encoding: .utf8) else {
            throw EnvironmentDocumentError.userNotesTooLarge
        }
        return AIDocumentSnapshot(content: content)
    }

    private func ensureExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: fileURL.path) else {
            try setSecurePermissions(of: fileURL)
            return
        }
        try atomicWrite(Data(Self.defaultContent.utf8), to: fileURL)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try setSecurePermissions(of: temporaryURL)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
            try setSecurePermissions(of: url)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func setSecurePermissions(of url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
