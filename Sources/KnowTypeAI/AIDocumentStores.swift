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
        return AIDocumentSnapshot(content: content)
    }

    public func replaceGeneratedSection(with generatedMarkdown: String) throws -> AIDocumentSnapshot {
        try ensureExists(defaultContent: Self.defaultContent)
        let current = try String(contentsOf: fileURL, encoding: .utf8)
        let next = Self.replacingGeneratedSection(in: current, with: generatedMarkdown)
        try atomicWrite(next, to: fileURL)
        return AIDocumentSnapshot(content: next)
    }

    public static func replacingGeneratedSection(in content: String, with generatedMarkdown: String) -> String {
        guard let startRange = content.range(of: generatedStart),
              let endRange = content.range(of: generatedEnd),
              startRange.upperBound <= endRange.lowerBound else {
            return """
            # KnowType Environment

            \(generatedStart)
            \(generatedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines))
            \(generatedEnd)

            ## User Notes
            """
        }
        var next = content
        let replacement = "\n\(generatedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        next.replaceSubrange(startRange.upperBound..<endRange.lowerBound, with: replacement)
        return next
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
