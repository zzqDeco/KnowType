import Foundation
import KnowTypeCore

public struct InputMethodLexiconRuntime: Sendable, Equatable {
    public static let environmentDirectoryKey = "KNOWTYPE_LEXICON_DIR"
    public static let environmentDirectoriesKey = "KNOWTYPE_LEXICON_DIRS"
    private static let cachedDefaultEngine = defaultRuntime().makeEngine()

    public var directories: [URL]

    public init(directories: [URL]) {
        self.directories = directories
    }

    public static func defaultRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> InputMethodLexiconRuntime {
        InputMethodLexiconRuntime(
            directories: defaultDirectories(
                environment: environment,
                homeDirectory: homeDirectory
            )
        )
    }

    public static func defaultDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var directories: [URL] = []
        directories.append(contentsOf: environmentDirectories(from: environment))
        directories.append(
            homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("KnowType")
                .appendingPathComponent("Lexicons")
        )
        return uniqueDirectories(directories)
    }

    public func loadCatalog(fileManager: FileManager = .default) -> TraditionalInputLexiconCatalog {
        let fileSource = TraditionalInputLexiconFileSource()
        var entries: [TraditionalInputLexiconEntry] = []
        var diagnostics: [TraditionalInputLexiconDiagnostic] = []

        for directory in directories where isDirectory(directory, fileManager: fileManager) {
            let catalog = fileSource.loadDirectory(directory)
            entries.append(contentsOf: catalog.entries)
            diagnostics.append(contentsOf: catalog.diagnostics)
        }

        return TraditionalInputLexiconCatalog(entries: entries, diagnostics: diagnostics)
    }

    public func makeEngine(fileManager: FileManager = .default) -> TraditionalInputEngine {
        loadCatalog(fileManager: fileManager).makeEngine()
    }

    public static func defaultEngine() -> TraditionalInputEngine {
        cachedDefaultEngine
    }

    private static func environmentDirectories(from environment: [String: String]) -> [URL] {
        var paths: [String] = []
        if let directory = environment[environmentDirectoryKey] {
            paths.append(directory)
        }
        if let directories = environment[environmentDirectoriesKey] {
            paths.append(contentsOf: directories.split(separator: ":").map(String.init))
        }
        return paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
    }

    private static func uniqueDirectories(_ directories: [URL]) -> [URL] {
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

    private func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
