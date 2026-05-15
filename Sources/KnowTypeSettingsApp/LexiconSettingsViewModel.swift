import Combine
import Foundation
import KnowTypeCore

public struct LexiconDiagnosticStatus: Sendable, Equatable, Identifiable {
    public var id: String {
        "\(resourceID):\(message)"
    }

    public var resourceID: String
    public var message: String

    public init(resourceID: String, message: String) {
        self.resourceID = resourceID
        self.message = message
    }
}

public struct LexiconDirectoryStatus: Sendable, Equatable, Identifiable {
    public var id: String {
        directory.standardizedFileURL.path
    }

    public var directory: URL
    public var exists: Bool
    public var resourceFileCount: Int
    public var loadedEntryCount: Int
    public var diagnostics: [LexiconDiagnosticStatus]

    public init(
        directory: URL,
        exists: Bool,
        resourceFileCount: Int,
        loadedEntryCount: Int,
        diagnostics: [LexiconDiagnosticStatus]
    ) {
        self.directory = directory
        self.exists = exists
        self.resourceFileCount = resourceFileCount
        self.loadedEntryCount = loadedEntryCount
        self.diagnostics = diagnostics
    }
}

@MainActor
public final class LexiconSettingsViewModel: ObservableObject {
    public static let environmentDirectoryKey = "KNOWTYPE_LEXICON_DIR"
    public static let environmentDirectoriesKey = "KNOWTYPE_LEXICON_DIRS"

    @Published public private(set) var directories: [LexiconDirectoryStatus]
    @Published public private(set) var totalLoadedEntryCount: Int
    @Published public private(set) var lastRefreshDate: Date?

    private let directoryURLs: [URL]
    private let fileManager: FileManager
    private let fileSource: TraditionalInputLexiconFileSource
    private let dateProvider: () -> Date

    public init(
        directoryURLs: [URL] = LexiconSettingsViewModel.defaultLexiconDirectories(),
        fileManager: FileManager = .default,
        fileSource: TraditionalInputLexiconFileSource = TraditionalInputLexiconFileSource(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.directoryURLs = Self.uniqueDirectories(directoryURLs)
        self.fileManager = fileManager
        self.fileSource = fileSource
        self.dateProvider = dateProvider
        self.directories = []
        self.totalLoadedEntryCount = 0
        refresh()
    }

    public static func defaultLexiconDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        var directories = environmentDirectories(from: environment)
        directories.append(
            homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("KnowType")
                .appendingPathComponent("Lexicons")
        )
        return uniqueDirectories(directories)
    }

    public func refresh() {
        let snapshots = directoryURLs.map(loadDirectoryStatus)
        directories = snapshots
        totalLoadedEntryCount = snapshots.reduce(0) { total, snapshot in
            total + snapshot.loadedEntryCount
        }
        lastRefreshDate = dateProvider()
    }

    private func loadDirectoryStatus(_ directory: URL) -> LexiconDirectoryStatus {
        guard isDirectory(directory) else {
            return LexiconDirectoryStatus(
                directory: directory,
                exists: false,
                resourceFileCount: 0,
                loadedEntryCount: 0,
                diagnostics: []
            )
        }

        let catalog = fileSource.loadDirectory(directory)
        return LexiconDirectoryStatus(
            directory: directory,
            exists: true,
            resourceFileCount: resourceFileCount(in: directory),
            loadedEntryCount: catalog.entries.count,
            diagnostics: catalog.diagnostics.map { diagnostic in
                LexiconDiagnosticStatus(
                    resourceID: diagnostic.resourceID,
                    message: diagnostic.error.localizedDescription
                )
            }
        )
    }

    private func isDirectory(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func resourceFileCount(in directory: URL) -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        return files.filter { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  TraditionalInputLexiconFileSource.format(for: url) != nil else {
                return false
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            return values?.isDirectory != true && values?.isHidden != true
        }.count
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
}
