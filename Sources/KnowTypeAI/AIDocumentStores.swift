import CryptoKit
import Foundation

public struct AIUserDirectory: Sendable, Equatable {
    public var rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static func defaultDirectory(
        fileManager: FileManager = .default
    ) -> AIUserDirectory {
        let home = fileManager.homeDirectoryForCurrentUser
        return AIUserDirectory(rootURL: home.appendingPathComponent(".knowtype", isDirectory: true))
    }

    public var environmentURL: URL {
        rootURL.appendingPathComponent("ENV.md", isDirectory: false)
    }

    public var correctionInstructionURL: URL {
        rootURL.appendingPathComponent("CORRECTION.md", isDirectory: false)
    }

    public var eventsDirectoryURL: URL {
        rootURL.appendingPathComponent("events", isDirectory: true)
    }

    public var lexicalProfileURL: URL {
        rootURL.appendingPathComponent("LEXICAL_PROFILE.md", isDirectory: false)
    }

    public var acceptedLearningMirrorURL: URL {
        rootURL.appendingPathComponent("ACCEPTED_AI_LEARNING.md", isDirectory: false)
    }
}

public struct AIDocumentSnapshot: Sendable, Equatable {
    public var content: String
    public var sha256: String

    public init(content: String) {
        self.content = content
        self.sha256 = Self.hash(content)
    }

    private static func hash(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct EnvironmentDocumentStore: @unchecked Sendable {
    public static let generatedStart = "<!-- KNOWTYPE:BEGIN GENERATED -->"
    public static let generatedEnd = "<!-- KNOWTYPE:END GENERATED -->"

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

    public init(
        fileURL: URL = AIUserDirectory.defaultDirectory().environmentURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadSnapshot() throws -> AIDocumentSnapshot {
        try ensureExists(defaultContent: Self.defaultContent)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let repaired = Self.repairingGeneratedSectionMarkers(in: content)
        if repaired != content {
            try? atomicWrite(repaired, to: fileURL)
        }
        return AIDocumentSnapshot(content: repaired)
    }

    public func replaceGeneratedSection(with generatedMarkdown: String) throws -> AIDocumentSnapshot {
        try ensureExists(defaultContent: Self.defaultContent)
        let current = try String(contentsOf: fileURL, encoding: .utf8)
        let next = Self.replacingGeneratedSection(in: current, with: generatedMarkdown)
        try atomicWrite(next, to: fileURL)
        return AIDocumentSnapshot(content: next)
    }

    public static func replacingGeneratedSection(in content: String, with generatedMarkdown: String) -> String {
        let content = repairingGeneratedSectionMarkers(in: content)
        let generated = generatedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startRange = content.range(of: generatedStart),
              let endRange = content.range(of: generatedEnd),
              startRange.upperBound <= endRange.lowerBound else {
            let preservedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            # KnowType Environment

            \(generatedStart)
            \(generated)
            \(generatedEnd)

            \(preservedContent)
            """
        }
        var next = content
        let replacement = "\n\(generated)\n"
        next.replaceSubrange(startRange.upperBound..<endRange.lowerBound, with: replacement)
        return next
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

            if marker == "## User Notes" {
                reachedUserNotes = true
            }

            if !reachedUserNotes,
               marker == generatedStart,
               let duplicateEndIndex = matchingGeneratedEndIndex(in: lines, from: index + 1) {
                removeTrailingDuplicateEnvironmentHeader(from: &repaired)
                index = duplicateEndIndex + 1
                continue
            }

            repaired.append(line)
            index += 1
        }

        guard completedFirstSection else {
            return content
        }
        return repaired.joined(separator: "\n")
    }

    private static func matchingGeneratedEndIndex(in lines: [String], from startIndex: Int) -> Int? {
        var index = startIndex
        while index < lines.count {
            let marker = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            switch marker {
            case generatedEnd:
                return index
            case generatedStart:
                return nil
            default:
                index += 1
            }
        }
        return nil
    }

    private static func removeTrailingDuplicateEnvironmentHeader(from lines: inout [String]) {
        var cursor = lines.count
        while cursor > 0, lines[cursor - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cursor -= 1
        }
        guard cursor > 0,
              lines[cursor - 1].trimmingCharacters(in: .whitespacesAndNewlines) == "# KnowType Environment" else {
            return
        }
        lines.removeSubrange((cursor - 1)..<lines.count)
    }

    private func ensureExists(defaultContent: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try atomicWrite(defaultContent, to: fileURL)
    }

    private func atomicWrite(_ content: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let data = Data(content.utf8)
        try data.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
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

    public init(
        fileURL: URL = AIUserDirectory.defaultDirectory().correctionInstructionURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadSnapshot() throws -> AIDocumentSnapshot {
        try ensureExists()
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return AIDocumentSnapshot(content: content)
    }

    private func ensureExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try Data(Self.defaultContent.utf8).write(to: fileURL, options: .atomic)
    }
}
