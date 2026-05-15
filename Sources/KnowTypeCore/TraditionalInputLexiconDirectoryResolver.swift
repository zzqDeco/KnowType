import Foundation

public struct TraditionalInputLexiconDirectoryResolver: Sendable, Equatable {
    public static let environmentDirectoryKey = "KNOWTYPE_LEXICON_DIR"
    public static let environmentDirectoriesKey = "KNOWTYPE_LEXICON_DIRS"

    public var environment: [String: String]
    public var homeDirectory: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    public func directories() -> [URL] {
        var directories = environmentDirectories()
        directories.append(Self.applicationSupportLexiconDirectory(homeDirectory: homeDirectory))
        return Self.uniqueDirectories(directories)
    }

    public static func defaultDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        TraditionalInputLexiconDirectoryResolver(
            environment: environment,
            homeDirectory: homeDirectory
        ).directories()
    }

    public static func applicationSupportLexiconDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("KnowType")
            .appendingPathComponent("Lexicons")
    }

    public static func uniqueDirectories(_ directories: [URL]) -> [URL] {
        var seen = Set<String>()
        return directories.filter { directory in
            let path = directory.standardizedFileURL.path
            guard !seen.contains(path) else {
                return false
            }
            seen.insert(path)
            return true
        }
    }

    private func environmentDirectories() -> [URL] {
        var paths: [String] = []
        if let directory = environment[Self.environmentDirectoryKey] {
            paths.append(directory)
        }
        if let directories = environment[Self.environmentDirectoriesKey] {
            paths.append(contentsOf: directories.split(separator: ":").map(String.init))
        }
        return paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
    }
}
